import type { AuthPrincipal } from "../auth/models.js";
import type { AcquisitionJobView, AcquisitionRequest, AcquisitionStore } from "./models.js";

export class MemoryAcquisitionStore implements AcquisitionStore {
  private readonly jobs = new Map<string, { userID: string; value: AcquisitionJobView }>();
  async create(principal: AuthPrincipal, request: AcquisitionRequest): Promise<AcquisitionJobView> {
    const now = new Date().toISOString();
    const value: AcquisitionJobView = { ...request, id: crypto.randomUUID(), state: "queued", progress: 0, attemptCount: 0,
      maxAttempts: 3, errorCode: null, errorDetail: null, catalogFileID: null, createdAt: now, updatedAt: now };
    this.jobs.set(value.id, { userID: principal.userId, value }); return value;
  }
  async list(principal: AuthPrincipal): Promise<AcquisitionJobView[]> { return [...this.jobs.values()].filter((job) => job.userID === principal.userId).map((job) => job.value); }
  async get(principal: AuthPrincipal, id: string): Promise<AcquisitionJobView | null> { const job = this.jobs.get(id); return job?.userID === principal.userId ? job.value : null; }
  async retry(principal: AuthPrincipal, id: string): Promise<AcquisitionJobView | null> {
    const job = this.jobs.get(id); if (!job || job.userID !== principal.userId || job.value.state !== "failed") return null;
    job.value = { ...job.value, state: "queued", progress: 0, errorCode: null, errorDetail: null, updatedAt: new Date().toISOString() };
    return job.value;
  }
}
