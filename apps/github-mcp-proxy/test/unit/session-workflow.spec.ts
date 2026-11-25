import { beforeEach, describe, expect, it } from 'vitest';
import {
  BadRequestProxyError,
  ConflictProxyError,
  NotFoundProxyError,
  UnprocessableProxyError,
  UpstreamGitHubError,
} from '../../src/common/errors';
import { loadProxyConfig, type ProxyConfig } from '../../src/config/proxy-config';
import { SessionService } from '../../src/sessions/session.service';
import { FakeGitHubApi } from '../fakes/fake-github-api';

describe('SessionService PR-backed write workflow', () => {
  let fakeGitHub: FakeGitHubApi;
  let config: ProxyConfig;
  let service: SessionService;
  let initialHeadSha: string;

  beforeEach(() => {
    fakeGitHub = new FakeGitHubApi();
    const seeded = fakeGitHub.seedRepository('btwld', 'wayfinder', {
      'wayfinder.json': JSON.stringify({
        version: 1,
        profiles: {
          demo: {
            source: { git: 'https://github.com/btwld/wayfinder', ref: 'main', path: 'profiles/bitwild' },
            applies_to: ['./knowledge'],
          },
        },
      }),
      'knowledge/index.md': '---\nokf_version: "0.2"\n---\n# Index\n',
      'knowledge/existing.md': '---\ntype: Note\ntitle: Existing\n---\nOld body\n',
    });
    initialHeadSha = seeded.headSha;
    config = loadProxyConfig({
      GITHUB_OWNER: 'btwld',
      GITHUB_REPO: 'wayfinder',
      GITHUB_TOKEN: 'ghp_test',
      SESSION_MERGE_RETRY_INITIAL_DELAY_MS: '5',
      SESSION_MERGE_RETRY_MAX_DELAY_MS: '10',
    });
    service = new SessionService(config, fakeGitHub);
  });

  it('starts a pending session without empty commit and lazily opens a Draft PR on first write', async () => {
    const started = await service.startSession({ sessionId: 's-lazy' }, 'ghp_test');
    expect(started.state).toBe('pending');
    expect(started.prNumber).toBeNull();
    expect(started.headSha).toBe(initialHeadSha);

    const written = await service.sessionWrite(
      {
        sessionId: 's-lazy',
        files: [
          { path: 'knowledge/new-note.md', content: '# New Note\nHello\n' },
          { path: 'knowledge/existing.md', delete: true },
        ],
      },
      'ghp_test',
    );

    expect(written.prNumber).toBe(1);
    expect(written.draft).toBe(true);
    expect(written.writtenPaths).toEqual(['knowledge/new-note.md']);
    expect(written.deletedPaths).toEqual(['knowledge/existing.md']);

    const details = await service.getSession({ sessionId: 's-lazy' }, 'ghp_test');
    expect(details.state).toBe('open');
    expect(details.changedFiles).toBe(2);
    expect(details.files.map((f) => f.filename)).toEqual([
      'knowledge/existing.md',
      'knowledge/new-note.md',
    ]);
  });

  it('falls back to non-draft PR when plan disallows drafts', async () => {
    fakeGitHub.failCreatePrWithDraftUnsupportedOnce = true;

    const started = await service.startSession(
      {
        sessionId: 's-nodraft',
        files: [{ path: 'knowledge/a.md', content: '# A\n' }],
      },
      'ghp_test',
    );

    expect(started.state).toBe('open');
    expect(started.draft).toBe(false);
    expect(started.prNumber).toBe(1);
  });

  it('rolls back orphan branch if createPullRequest fails after branch creation', async () => {
    fakeGitHub.failCreatePrWithError = new UpstreamGitHubError(500, 'GitHub PR service down');

    await expect(
      service.startSession(
        {
          sessionId: 's-rollback',
          files: [{ path: 'knowledge/a.md', content: '# A\n' }],
        },
        'ghp_test',
      ),
    ).rejects.toThrow(UpstreamGitHubError);

    expect(fakeGitHub.getBranchSha('btwld', 'wayfinder', 'wayfinder/session/s-rollback')).toBeUndefined();
  });

  it('supports autoStart on session_write and optimistic expectedHeadSha locking', async () => {
    const auto = await service.sessionWrite(
      {
        autoStart: true,
        files: [{ path: 'knowledge/auto.md', content: '# Auto\n' }],
      },
      'ghp_test',
    );

    expect(auto.autoStarted).toBe(true);
    expect(auto.prNumber).toBe(1);

    await expect(
      service.sessionWrite(
        {
          sessionId: auto.sessionId,
          expectedHeadSha: 'stale-sha-000',
          files: [{ path: 'knowledge/auto.md', content: '# Updated\n' }],
        },
        'ghp_test',
      ),
    ).rejects.toThrow(ConflictProxyError);
  });

  it('refuses empty sessions on commit_session', async () => {
    await service.startSession({ sessionId: 's-empty' }, 'ghp_test');

    await expect(
      service.commitSession({ sessionId: 's-empty' }, 'ghp_test'),
    ).rejects.toThrow(UnprocessableProxyError);
  });

  it('verifies check runs when requireChecks=true, marks draft ready, retries transient 405, merges, and deletes branch', async () => {
    const started = await service.startSession(
      {
        sessionId: 's-commit',
        files: [{ path: 'knowledge/ready.md', content: '# Ready\n' }],
      },
      'ghp_test',
    );

    // Fails when checks are missing/failing
    await expect(
      service.commitSession(
        { sessionId: 's-commit', requireChecks: true },
        'ghp_test',
      ),
    ).rejects.toThrow(ConflictProxyError);

    fakeGitHub.setCheckRuns('btwld', 'wayfinder', started.headSha, [
      { id: 1, name: 'Required checks', status: 'completed', conclusion: 'success', htmlUrl: null },
    ]);

    fakeGitHub.transientMerge405Count = 2;

    const committed = await service.commitSession(
      {
        sessionId: 's-commit',
        expectedHeadSha: started.headSha,
        requireChecks: true,
        mergeMethod: 'squash',
      },
      'ghp_test',
    );

    expect(committed.merged).toBe(true);
    expect(committed.mergeMethod).toBe('squash');
    expect(committed.branchDeleted).toBe(true);
    expect(committed.checksVerified).toBe(true);
    expect(fakeGitHub.getBranchSha('btwld', 'wayfinder', 'wayfinder/session/s-commit')).toBeUndefined();
  });

  it('closes a session with a reason comment and deletes the branch without merging', async () => {
    const started = await service.startSession(
      {
        sessionId: 's-close',
        files: [{ path: 'knowledge/discard.md', content: '# Discard\n' }],
      },
      'ghp_test',
    );

    const closed = await service.closeSession(
      {
        sessionId: 's-close',
        reason: 'Superseded by manual edit',
      },
      'ghp_test',
    );

    expect(closed.state).toBe('closed');
    expect(closed.commentPosted).toBe(true);
    expect(closed.branchDeleted).toBe(true);
    expect(fakeGitHub.getPrComments('btwld', 'wayfinder', started.prNumber!)[0].body).toBe(
      'Superseded by manual edit',
    );
    expect(fakeGitHub.getBranchSha('btwld', 'wayfinder', 'wayfinder/session/s-close')).toBeUndefined();
  });

  it('rejects non-default baseBranch or custom PR metadata on file-less lazy startSession', async () => {
    await expect(
      service.startSession({ sessionId: 's-bad-lazy', title: 'Custom' }, 'ghp_test'),
    ).rejects.toThrow(BadRequestProxyError);

    await expect(
      service.startSession({ sessionId: 's-bad-draft', draft: false }, 'ghp_test'),
    ).rejects.toThrow(BadRequestProxyError);

    expect(fakeGitHub.getBranchSha('btwld', 'wayfinder', 'wayfinder/session/s-bad-lazy')).toBeUndefined();
  });

  it('prevents Draft TOCTOU merge when branch advances before markPullRequestReadyForReview', async () => {
    const started = await service.startSession(
      {
        sessionId: 's-toctou',
        files: [{ path: 'knowledge/checked.md', content: '# Checked\n' }],
      },
      'ghp_test',
    );

    fakeGitHub.setCheckRuns('btwld', 'wayfinder', started.headSha, [
      { id: 1, name: 'ci', status: 'completed', conclusion: 'success', htmlUrl: null },
    ]);

    fakeGitHub.onBeforeMarkReady = async () => {
      await service.sessionWrite(
        {
          sessionId: 's-toctou',
          files: [{ path: 'knowledge/unchecked.md', content: '# Unchecked\n' }],
        },
        'ghp_test',
      );
    };

    await expect(
      service.commitSession(
        {
          sessionId: 's-toctou',
          expectedHeadSha: started.headSha,
          requireChecks: true,
        },
        'ghp_test',
      ),
    ).rejects.toThrow(ConflictProxyError);
  });

  it('evaluates requiredCheckNames using latest rerun, fails fast on mergeable=false, and handles autoDeleteBranchOnMerge', async () => {
    const started = await service.startSession(
      {
        sessionId: 's-checks',
        files: [{ path: 'knowledge/ci.md', content: '# CI\n' }],
      },
      'ghp_test',
    );

    // Older failed run (id: 1) superseded by rerun (id: 2)
    fakeGitHub.setCheckRuns('btwld', 'wayfinder', started.headSha, [
      { id: 1, name: 'Required checks', status: 'completed', conclusion: 'failure', htmlUrl: null },
      { id: 2, name: 'Required checks', status: 'completed', conclusion: 'success', htmlUrl: null },
      { id: 3, name: 'Optional lint', status: 'completed', conclusion: 'failure', htmlUrl: null },
    ]);

    await expect(
      service.commitSession(
        {
          sessionId: 's-checks',
          requireChecks: true,
          requiredCheckNames: ['Required checks', 'Missing check'],
        },
        'ghp_test',
      ),
    ).rejects.toThrow(ConflictProxyError);

    fakeGitHub.forceMergeableFalse = true;
    await expect(
      service.commitSession(
        {
          sessionId: 's-checks',
          requireChecks: true,
          requiredCheckNames: ['Required checks'],
        },
        'ghp_test',
      ),
    ).rejects.toThrow(ConflictProxyError);

    fakeGitHub.forceMergeableFalse = false;
    fakeGitHub.autoDeleteBranchOnMerge = true;
    const merged = await service.commitSession(
      {
        sessionId: 's-checks',
        requireChecks: true,
        requiredCheckNames: ['Required checks'],
      },
      'ghp_test',
    );
    expect(merged.merged).toBe(true);
    expect(merged.branchDeleted).toBe(false);
  });

  it('lists sessions accurately across states, hydrates changedFiles, filters forks, and handles deleteBranch=false & reused sessionIds', async () => {
    await service.startSession({ sessionId: 's-pend' }, 'ghp_test');
    await service.startSession(
      { sessionId: 's-kept', files: [{ path: 'knowledge/k.md', content: '# Kept\n' }] },
      'ghp_test',
    );
    fakeGitHub.seedForkPullRequest('btwld', 'wayfinder', 'external-fork', 'wayfinder/session/fork-1');

    // Commit s-kept while keeping its branch
    await service.commitSession({ sessionId: 's-kept', deleteBranch: false }, 'ghp_test');

    const openList = await service.listSessions({ state: 'open' }, 'ghp_test');
    expect(openList.sessions.map((s) => s.sessionId)).toEqual(['s-pend']);

    const allList = await service.listSessions({ state: 'all' }, 'ghp_test');
    expect(allList.sessions.map((s) => `${s.sessionId}:${s.state}`)).toEqual([
      's-kept:merged',
      's-pend:pending',
    ]);
    expect(allList.sessions[0].changedFiles).toBe(1);
    expect(allList.sessions[0].mergeable).toBe(true);

    // Reusing a previously merged & branch-deleted sessionId reports the new live pending session
    await service.startSession(
      { sessionId: 's-reuse', files: [{ path: 'knowledge/r1.md', content: '# R1\n' }] },
      'ghp_test',
    );
    await service.commitSession({ sessionId: 's-reuse' }, 'ghp_test');
    await service.startSession({ sessionId: 's-reuse' }, 'ghp_test');
    const reused = await service.getSession({ sessionId: 's-reuse' }, 'ghp_test');
    expect(reused.state).toBe('pending');
    expect(reused.prNumber).toBeNull();
  });

  it('rejects closeSession on pending session with deleteBranch=false, rolls back autoStart errors, and 404s unknown session', async () => {
    await service.startSession({ sessionId: 's-pending-close' }, 'ghp_test');

    await expect(
      service.closeSession({ sessionId: 's-pending-close', deleteBranch: false }, 'ghp_test'),
    ).rejects.toThrow(BadRequestProxyError);

    const closed = await service.closeSession({ sessionId: 's-pending-close' }, 'ghp_test');
    expect(closed.branchDeleted).toBe(true);

    await expect(
      service.closeSession({ sessionId: 's-does-not-exist' }, 'ghp_test'),
    ).rejects.toThrow(NotFoundProxyError);

    fakeGitHub.failCreatePrWithError = new UpstreamGitHubError(500, 'PR create failed');
    await expect(
      service.sessionWrite(
        {
          sessionId: 's-autostart-fail',
          autoStart: true,
          files: [{ path: 'knowledge/a.md', content: '# A\n' }],
        },
        'ghp_test',
      ),
    ).rejects.toThrow(UpstreamGitHubError);
    expect(
      fakeGitHub.getBranchSha('btwld', 'wayfinder', 'wayfinder/session/s-autostart-fail'),
    ).toBeUndefined();
  });
});
