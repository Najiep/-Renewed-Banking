export type BankingError = { code: string; message?: string; details?: Record<string, unknown> };
export type Result<T> = { ok: true; data: T } | { ok: false; error: BankingError };
export type AccountSummary = { kind: 'personal' | 'database'; key: string; displayName: string; accountType: 'personal' | 'job' | 'gang' | 'shared' | 'system' | 'admin'; balance: number; cash?: number; currency: string; status: 'active' | 'frozen' | 'closed' | 'migration_hold'; role: string; permissions: Record<string, boolean> };
export type BankingSession = { framework: 'esx' | 'qb' | 'qbx'; currency: { code: string; symbol: string; precision: number }; accounts: AccountSummary[]; migrationRequired: boolean; capabilities: { sharedAccounts: boolean } };
