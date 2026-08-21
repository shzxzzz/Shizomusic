import type { AuthPrincipal } from "../auth/models.js";
import type { AcquisitionMethod, ExternalEntityReference } from "../search/models.js";

export type AcquisitionState = "queued" | "running" | "postProcessing" | "completed" | "failed";
export interface AcquisitionRequest {
  reference: ExternalEntityReference;
  method: AcquisitionMethod;
  title: string;
  artist: string | null;
  artworkURL: string | null;
}
export interface AcquisitionJobView extends AcquisitionRequest {
  id: string;
  state: AcquisitionState;
  progress: number;
  attemptCount: number;
  maxAttempts: number;
  errorCode: string | null;
  errorDetail: string | null;
  catalogFileID: string | null;
  createdAt: string;
  updatedAt: string;
}
export interface AcquisitionStore {
  create(principal: AuthPrincipal, request: AcquisitionRequest): Promise<AcquisitionJobView>;
  list(principal: AuthPrincipal): Promise<AcquisitionJobView[]>;
  get(principal: AuthPrincipal, id: string): Promise<AcquisitionJobView | null>;
  retry(principal: AuthPrincipal, id: string): Promise<AcquisitionJobView | null>;
}

const allowedMethods = new Set<AcquisitionMethod>(["direct", "yt_dlp", "spotdl"]);
export function validateAcquisitionRequest(value: unknown): AcquisitionRequest {
  if (!value || typeof value !== "object") throw new Error("invalid_acquisition");
  const body = value as Record<string, unknown>; const reference = body.reference as Record<string, unknown> | undefined;
  const method = body.method as AcquisitionMethod;
  if (!reference || typeof reference.provider !== "string" || !["track", "artist", "release"].includes(String(reference.entityType))
      || typeof reference.externalID !== "string" || !reference.externalID || !allowedMethods.has(method)
      || typeof body.title !== "string" || !body.title.trim()) throw new Error("invalid_acquisition");
  const canonicalURL = typeof reference.canonicalURL === "string" ? reference.canonicalURL : null;
  if (method !== "direct" && !canonicalURL) throw new Error("acquisition_url_required");
  const provider = reference.provider;
  if ((method === "direct" && provider !== "audius") || (method === "yt_dlp" && provider !== "piped") || (method === "spotdl" && provider !== "spotify")) {
    throw new Error("acquisition_method_provider_mismatch");
  }
  if (canonicalURL) { const url = new URL(canonicalURL); if (url.protocol !== "https:") throw new Error("invalid_acquisition_url"); }
  return { reference: { provider: reference.provider, entityType: reference.entityType as "track" | "artist" | "release", externalID: reference.externalID, canonicalURL },
    method, title: body.title.trim().slice(0, 500), artist: typeof body.artist === "string" ? body.artist.slice(0, 500) : null,
    artworkURL: typeof body.artworkURL === "string" ? body.artworkURL.slice(0, 2_000) : null };
}
