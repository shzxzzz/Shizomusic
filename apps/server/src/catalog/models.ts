import type { AuthPrincipal } from "../auth/models.js";

export interface UploadRequest {
  filename: string;
  mimeType: string;
  byteSize: string;
  sha256: string;
  partSize?: number;
}

export interface UploadSessionView {
  id: string;
  partSize: number;
  totalParts: number;
  uploadedParts: number[];
  expiresAt: string;
  alreadyAvailableFileId?: string;
}

export interface CatalogTrackView {
  id: string;
  contentHash: string;
  byteSize: string;
  mimeType: string;
  filename: string;
  status: string;
  title: string;
  artist: string;
  album: string | null;
  albumArtist: string | null;
  duration: number;
  format: string | null;
  codec: string | null;
  addedBy: { id: string; displayName: string };
  streamPath: string;
  artworkPath: string | null;
  createdAt: string;
}

export interface StoredObject { path?: string; bytes?: Buffer; size: bigint; mimeType: string; etag: string }

export interface CatalogStore {
  createUpload(principal: AuthPrincipal, request: UploadRequest): Promise<UploadSessionView>;
  putPart(principal: AuthPrincipal, uploadId: string, partNumber: number, bytes: Buffer, sha256: string): Promise<void>;
  completeUpload(principal: AuthPrincipal, uploadId: string): Promise<{ fileId: string; contentHash: string; status: string }>;
  cancelUpload(principal: AuthPrincipal, uploadId: string): Promise<void>;
  listCatalog(): Promise<CatalogTrackView[]>;
  findByExternalReference?(provider: string, entityType: string, externalID: string): Promise<CatalogTrackView | null>;
  object(contentHash: string, artwork: boolean): Promise<StoredObject | null>;
}
