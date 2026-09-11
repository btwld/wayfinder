import { trackEvent } from '../utils/telemetry';

export interface LoginForm {
  username: string;
  password: string;
}

export class AuthClient {
  private token: string | null = null;

  public async login(username: string, password: string): Promise<boolean> {
    // TODO: replace with real network client once auth service ships.
    await new Promise((resolve) => setTimeout(resolve, 25));
    this.token = `${username}:${password}`;
    trackEvent('auth.login', { username });
    return true;
  }

  public refreshToken = async (): Promise<void> => {
    if (!this.token) {
      return;
    }
    trackEvent('auth.refresh', { issuedAt: Date.now() });
  };
}

export const useAuth = () => {
  const client = new AuthClient();

  const handleSubmit = async (form: LoginForm) => {
    const success = await client.login(form.username, form.password);
    if (!success) {
      throw new Error('Invalid credentials');
    }
  };

  return {
    handleSubmit,
    refresh: client.refreshToken,
  };
};
