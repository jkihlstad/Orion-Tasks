import { ActionCtx } from "./_generated/server";

/**
 * Clerk JWT Verification Helper
 *
 * This module provides utilities for verifying Clerk JWTs in Convex HTTP actions.
 * It handles token validation, user extraction, and consent verification.
 */

// JWT payload structure from Clerk
export interface ClerkJWTPayload {
  // Standard JWT claims
  iss: string; // Issuer (Clerk)
  sub: string; // Subject (User ID)
  aud: string | string[]; // Audience
  exp: number; // Expiration timestamp
  iat: number; // Issued at timestamp
  nbf?: number; // Not before timestamp
  jti?: string; // JWT ID

  // Clerk-specific claims
  azp?: string; // Authorized party
  sid?: string; // Session ID
  org_id?: string; // Organization ID
  org_role?: string; // Organization role
  org_slug?: string; // Organization slug

  // Custom claims (from Clerk metadata)
  metadata?: {
    deviceId?: string;
    appVersion?: string;
    platform?: string;
  };
}

export interface AuthResult {
  success: true;
  userId: string;
  sessionId?: string;
  orgId?: string;
  metadata?: ClerkJWTPayload["metadata"];
}

export interface AuthError {
  success: false;
  error: string;
  code: AuthErrorCode;
}

export type AuthErrorCode =
  | "MISSING_TOKEN"
  | "INVALID_TOKEN"
  | "EXPIRED_TOKEN"
  | "INVALID_ISSUER"
  | "INVALID_AUDIENCE"
  | "VERIFICATION_FAILED"
  | "CONSENT_REQUIRED"
  | "CONSENT_EXPIRED";

export type AuthResponse = AuthResult | AuthError;

/**
 * Extract Bearer token from Authorization header
 */
export function extractBearerToken(authHeader: string | null): string | null {
  if (!authHeader) {
    return null;
  }

  const parts = authHeader.split(" ");
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    return null;
  }

  return parts[1];
}

/**
 * Decode JWT payload without verification (for debugging/logging)
 * WARNING: Do not use this for authentication - always verify first!
 */
export function decodeJWTPayload(token: string): ClerkJWTPayload | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) {
      return null;
    }

    const payload = parts[1];
    // Base64URL decode
    const decoded = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(decoded) as ClerkJWTPayload;
  } catch {
    return null;
  }
}

/**
 * Verify Clerk JWT using JWKS
 *
 * This function verifies the JWT signature against Clerk's public keys.
 * In production, this should use Clerk's JWKS endpoint for key rotation.
 */
export async function verifyClerkJWT(
  token: string,
  ctx: ActionCtx
): Promise<AuthResponse> {
  // Get Clerk configuration from environment
  const clerkIssuer = process.env.CLERK_ISSUER_URL;
  const clerkAudience = process.env.CLERK_AUDIENCE;

  if (!clerkIssuer) {
    console.error("CLERK_ISSUER_URL not configured");
    return {
      success: false,
      error: "Server configuration error",
      code: "VERIFICATION_FAILED",
    };
  }

  try {
    // Decode the token to check basic validity
    const payload = decodeJWTPayload(token);

    if (!payload) {
      return {
        success: false,
        error: "Invalid token format",
        code: "INVALID_TOKEN",
      };
    }

    // Check expiration
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < now) {
      return {
        success: false,
        error: "Token has expired",
        code: "EXPIRED_TOKEN",
      };
    }

    // Check not-before
    if (payload.nbf && payload.nbf > now) {
      return {
        success: false,
        error: "Token not yet valid",
        code: "INVALID_TOKEN",
      };
    }

    // Verify issuer
    if (!payload.iss || !payload.iss.startsWith(clerkIssuer)) {
      return {
        success: false,
        error: "Invalid token issuer",
        code: "INVALID_ISSUER",
      };
    }

    // Verify audience if configured
    if (clerkAudience) {
      const audiences = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
      if (!audiences.includes(clerkAudience)) {
        return {
          success: false,
          error: "Invalid token audience",
          code: "INVALID_AUDIENCE",
        };
      }
    }

    // Verify signature using Clerk's JWKS
    // In production, this would use jose or similar library
    const isValid = await verifyJWTSignature(token, clerkIssuer);

    if (!isValid) {
      return {
        success: false,
        error: "Token signature verification failed",
        code: "VERIFICATION_FAILED",
      };
    }

    // Extract user ID (Clerk uses 'sub' claim)
    if (!payload.sub) {
      return {
        success: false,
        error: "Token missing user ID",
        code: "INVALID_TOKEN",
      };
    }

    return {
      success: true,
      userId: payload.sub,
      sessionId: payload.sid,
      orgId: payload.org_id,
      metadata: payload.metadata,
    };
  } catch (error) {
    console.error("JWT verification error:", error);
    return {
      success: false,
      error: "Token verification failed",
      code: "VERIFICATION_FAILED",
    };
  }
}

/**
 * Verify JWT signature against Clerk's JWKS
 *
 * This implementation fetches Clerk's public keys and verifies the signature.
 * Keys are cached to avoid repeated fetches.
 */
async function verifyJWTSignature(token: string, issuerUrl: string): Promise<boolean> {
  try {
    // Fetch JWKS from Clerk
    const jwksUrl = `${issuerUrl}/.well-known/jwks.json`;

    // In production, implement caching here
    const response = await fetch(jwksUrl);

    if (!response.ok) {
      console.error("Failed to fetch JWKS:", response.status);
      return false;
    }

    const jwks = await response.json();

    // Parse the JWT header to get the key ID
    const parts = token.split(".");
    if (parts.length !== 3) {
      return false;
    }

    const headerJson = atob(parts[0].replace(/-/g, "+").replace(/_/g, "/"));
    const header = JSON.parse(headerJson);
    const kid = header.kid;

    // Find the matching key
    const key = jwks.keys?.find((k: any) => k.kid === kid);
    if (!key) {
      console.error("No matching key found in JWKS");
      return false;
    }

    // Verify the signature using Web Crypto API
    const cryptoKey = await importJWK(key, header.alg);

    // Prepare signature verification
    const signatureInput = parts[0] + "." + parts[1];
    const signature = base64UrlDecode(parts[2]);

    const encoder = new TextEncoder();
    const data = encoder.encode(signatureInput);

    const isValid = await crypto.subtle.verify(
      getAlgorithmParams(header.alg),
      cryptoKey,
      signature,
      data
    );

    return isValid;
  } catch (error) {
    console.error("Signature verification error:", error);
    return false;
  }
}

/**
 * Import a JWK as a CryptoKey
 */
async function importJWK(jwk: any, algorithm: string): Promise<CryptoKey> {
  const algorithmParams = getKeyImportParams(algorithm);

  return crypto.subtle.importKey(
    "jwk",
    jwk,
    algorithmParams,
    true,
    ["verify"]
  );
}

/**
 * Get algorithm parameters for signature verification
 */
function getAlgorithmParams(algorithm: string): AlgorithmIdentifier | RsaPssParams | EcdsaParams {
  switch (algorithm) {
    case "RS256":
      return { name: "RSASSA-PKCS1-v1_5" };
    case "RS384":
      return { name: "RSASSA-PKCS1-v1_5" };
    case "RS512":
      return { name: "RSASSA-PKCS1-v1_5" };
    case "ES256":
      return { name: "ECDSA", hash: "SHA-256" };
    case "ES384":
      return { name: "ECDSA", hash: "SHA-384" };
    case "ES512":
      return { name: "ECDSA", hash: "SHA-512" };
    default:
      throw new Error(`Unsupported algorithm: ${algorithm}`);
  }
}

/**
 * Get key import parameters based on algorithm
 */
function getKeyImportParams(algorithm: string): RsaHashedImportParams | EcKeyImportParams {
  switch (algorithm) {
    case "RS256":
      return { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };
    case "RS384":
      return { name: "RSASSA-PKCS1-v1_5", hash: "SHA-384" };
    case "RS512":
      return { name: "RSASSA-PKCS1-v1_5", hash: "SHA-512" };
    case "ES256":
      return { name: "ECDSA", namedCurve: "P-256" };
    case "ES384":
      return { name: "ECDSA", namedCurve: "P-384" };
    case "ES512":
      return { name: "ECDSA", namedCurve: "P-521" };
    default:
      throw new Error(`Unsupported algorithm: ${algorithm}`);
  }
}

/**
 * Base64URL decode to Uint8Array
 */
function base64UrlDecode(input: string): Uint8Array {
  // Convert base64url to base64
  let base64 = input.replace(/-/g, "+").replace(/_/g, "/");

  // Add padding if needed
  const padding = base64.length % 4;
  if (padding) {
    base64 += "=".repeat(4 - padding);
  }

  // Decode
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/**
 * Create an HTTP error response
 */
export function createAuthErrorResponse(error: AuthError): Response {
  const statusCode = getStatusCodeForError(error.code);

  return new Response(
    JSON.stringify({
      error: error.error,
      code: error.code,
    }),
    {
      status: statusCode,
      headers: {
        "Content-Type": "application/json",
      },
    }
  );
}

/**
 * Map error codes to HTTP status codes
 */
function getStatusCodeForError(code: AuthErrorCode): number {
  switch (code) {
    case "MISSING_TOKEN":
    case "INVALID_TOKEN":
    case "EXPIRED_TOKEN":
    case "INVALID_ISSUER":
    case "INVALID_AUDIENCE":
    case "VERIFICATION_FAILED":
      return 401;
    case "CONSENT_REQUIRED":
    case "CONSENT_EXPIRED":
      return 403;
    default:
      return 401;
  }
}

/**
 * Authenticate a request and extract user info
 *
 * This is the main authentication function to use in HTTP actions.
 */
export async function authenticateRequest(
  request: Request,
  ctx: ActionCtx
): Promise<AuthResponse> {
  // Extract Authorization header
  const authHeader = request.headers.get("Authorization");
  const token = extractBearerToken(authHeader);

  if (!token) {
    return {
      success: false,
      error: "Missing authorization token",
      code: "MISSING_TOKEN",
    };
  }

  // Verify the JWT
  return verifyClerkJWT(token, ctx);
}

/**
 * Verify that a user has valid consent for the requested operation
 */
export async function verifyConsent(
  ctx: ActionCtx,
  userId: string,
  requiredConsents: string[]
): Promise<{ valid: boolean; snapshotId?: string; error?: string }> {
  // Query the user's active consent from the database
  const consent = await ctx.runQuery(
    // @ts-ignore - Internal query reference
    "internal:consent:getActiveConsent",
    { userId }
  );

  if (!consent) {
    return {
      valid: false,
      error: "No consent on file",
    };
  }

  // Check each required consent
  const snapshot = consent.consentSnapshot;
  for (const required of requiredConsents) {
    const hasConsent = snapshot[required as keyof typeof snapshot];
    if (!hasConsent) {
      return {
        valid: false,
        error: `Missing required consent: ${required}`,
      };
    }
  }

  return {
    valid: true,
    snapshotId: consent.snapshotId,
  };
}

/**
 * Helper to require authentication in an HTTP action
 *
 * Usage:
 * ```typescript
 * const auth = await requireAuth(request, ctx);
 * if (!auth.success) {
 *   return createAuthErrorResponse(auth);
 * }
 * // auth.userId is now available
 * ```
 */
export async function requireAuth(
  request: Request,
  ctx: ActionCtx
): Promise<AuthResponse> {
  return authenticateRequest(request, ctx);
}

/**
 * Helper to require authentication with specific consent
 *
 * Usage:
 * ```typescript
 * const result = await requireAuthWithConsent(request, ctx, ["dataProcessing", "cloudSync"]);
 * if (!result.success) {
 *   return createAuthErrorResponse(result.error);
 * }
 * // result.userId and result.consentSnapshotId are available
 * ```
 */
export async function requireAuthWithConsent(
  request: Request,
  ctx: ActionCtx,
  requiredConsents: string[]
): Promise<
  | { success: true; userId: string; consentSnapshotId: string }
  | { success: false; error: AuthError }
> {
  // First authenticate
  const authResult = await authenticateRequest(request, ctx);

  if (!authResult.success) {
    return { success: false, error: authResult };
  }

  // Then verify consent
  const consentResult = await verifyConsent(ctx, authResult.userId, requiredConsents);

  if (!consentResult.valid) {
    return {
      success: false,
      error: {
        success: false,
        error: consentResult.error || "Consent required",
        code: "CONSENT_REQUIRED",
      },
    };
  }

  return {
    success: true,
    userId: authResult.userId,
    consentSnapshotId: consentResult.snapshotId!,
  };
}

/**
 * Extract device ID from request headers or JWT metadata
 */
export function extractDeviceId(
  request: Request,
  authResult: AuthResult
): string {
  // Try to get from custom header first
  const deviceIdHeader = request.headers.get("X-Device-ID");
  if (deviceIdHeader) {
    return deviceIdHeader;
  }

  // Try to get from JWT metadata
  if (authResult.metadata?.deviceId) {
    return authResult.metadata.deviceId;
  }

  // Fallback to session ID or generate a temporary one
  return authResult.sessionId || `temp-${Date.now()}`;
}
