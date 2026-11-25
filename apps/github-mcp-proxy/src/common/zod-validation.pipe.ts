import { ArgumentMetadata, Injectable, PipeTransform } from '@nestjs/common';
import { z } from 'zod';
import { BadRequestProxyError } from './errors';

export interface ZodValidationPipeOptions {
  coerceQuery?: boolean;
  defaultEmptyObject?: boolean;
}

function unwrapSchema(schema: unknown): z.ZodType | undefined {
  let current: unknown = schema;
  for (let i = 0; i < 8 && current && typeof current === 'object'; i++) {
    if (
      current instanceof z.ZodOptional ||
      current instanceof z.ZodNullable ||
      current instanceof z.ZodDefault
    ) {
      current = current.unwrap();
      continue;
    }
    if (current instanceof z.ZodPipe) {
      current = (current as unknown as { in?: unknown }).in;
      continue;
    }
    break;
  }
  return current instanceof z.ZodType ? current : undefined;
}

function extractObjectShape(schema: z.ZodType): Record<string, z.ZodType> | undefined {
  const inner = unwrapSchema(schema);
  if (inner instanceof z.ZodObject) {
    return inner.shape as Record<string, z.ZodType>;
  }
  return undefined;
}

function coerceFieldValue(raw: unknown, fieldSchema: z.ZodType): unknown {
  const inner = unwrapSchema(fieldSchema);
  if (!inner) return raw;

  if (inner instanceof z.ZodBoolean) {
    if (typeof raw === 'string') {
      const lower = raw.trim().toLowerCase();
      if (lower === 'true' || lower === '1') return true;
      if (lower === 'false' || lower === '0') return false;
    }
    return raw;
  }

  if (inner instanceof z.ZodNumber) {
    if (typeof raw === 'string' && raw.trim() !== '') {
      const num = Number(raw);
      if (Number.isFinite(num)) return num;
    }
    return raw;
  }

  if (inner instanceof z.ZodArray) {
    if (typeof raw === 'string') {
      return raw
        .split(',')
        .map((item) => item.trim())
        .filter(Boolean);
    }
    return raw;
  }

  return raw;
}

@Injectable()
export class ZodValidationPipe<T extends z.ZodType> implements PipeTransform {
  constructor(
    private readonly schema: T,
    private readonly options: ZodValidationPipeOptions = {},
  ) {}

  transform(value: unknown, _metadata?: ArgumentMetadata): z.infer<T> {
    const normalized =
      this.options.defaultEmptyObject && value === undefined ? {} : value;
    const candidate = this.options.coerceQuery
      ? this.coerceQueryObject(normalized)
      : normalized;
    const parsed = this.schema.safeParse(candidate);
    if (!parsed.success) {
      const issues = parsed.error.issues.map((issue) => ({
        path: issue.path.join('.'),
        message: issue.message,
        code: issue.code,
      }));
      const summary = issues
        .map((issue) => (issue.path ? `${issue.path}: ${issue.message}` : issue.message))
        .join('; ');
      throw new BadRequestProxyError(`Validation failed: ${summary}`, { issues });
    }
    return parsed.data;
  }

  private coerceQueryObject(value: unknown): unknown {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return value;
    }
    const shape = extractObjectShape(this.schema);
    if (!shape) return value;

    const record = value as Record<string, unknown>;
    const next: Record<string, unknown> = { ...record };
    for (const [key, fieldSchema] of Object.entries(shape)) {
      if (next[key] === undefined || next[key] === '') {
        if (next[key] === '') delete next[key];
        continue;
      }
      next[key] = coerceFieldValue(next[key], fieldSchema);
    }
    return next;
  }
}
