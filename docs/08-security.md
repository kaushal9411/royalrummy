# Security Architecture — RummyRoyale

## 1. Security Layers

```
Layer 1: Network       — Cloudflare WAF, DDoS protection, TLS 1.3
Layer 2: API Gateway   — Rate limiting, JWT validation, request signing
Layer 3: Application   — Input validation, RBAC, audit logging
Layer 4: Data          — Encryption at rest, column encryption, PII masking
Layer 5: Device        — Root/emulator detection, SSL pinning, device binding
Layer 6: Game          — Server-side validation, anti-cheat engine
Layer 7: Wallet        — Atomic locks, fraud detection, KYC
```

---

## 2. Authentication & JWT

### Token Architecture
```typescript
// Access token: 15 minutes, stateless JWT
{
  sub: "user-uuid",
  username: "rummyking",
  role: "player",
  device_id: "ANDROID-xxxx",
  iat: 1700000000,
  exp: 1700000900,  // +15 min
  jti: "unique-token-id"  // Prevent replay attacks
}

// Refresh token: 30 days, stored in DB (can be revoked)
{
  sub: "user-uuid",
  device_id: "ANDROID-xxxx",
  token_family: "family-uuid",  // Rotation tracking
  iat: 1700000000,
  exp: 1702592000
}
```

### Token Rotation (Refresh Token Reuse Detection)
```typescript
async refreshTokens(refreshToken: string, deviceId: string) {
  const decoded = this.jwtService.verify(refreshToken);
  const storedToken = await this.findToken(decoded.jti);

  if (!storedToken || storedToken.revoked_at) {
    // Token reuse detected — revoke entire family
    await this.revokeTokenFamily(decoded.token_family);
    throw new UnauthorizedException('TOKEN_REUSE_DETECTED');
  }

  // Revoke old token, issue new pair
  await this.revokeToken(storedToken.id);
  return this.issueTokenPair(decoded.sub, deviceId, decoded.token_family);
}
```

---

## 3. Device Binding & Fingerprinting

```typescript
// Device fingerprint components (Android)
interface DeviceFingerprint {
  device_id: string;        // UUID stored in secure storage
  android_id: string;       // Persistent Android ID
  hardware_id: string;      // Board + brand + device hash
  app_signature: string;    // APK signature hash
  build_fingerprint: string;
}

// Server validates device fingerprint on each sensitive operation
async validateDevice(userId: string, deviceId: string, fingerprint: string) {
  const trusted = await this.deviceRepo.findOne({
    where: { user_id: userId, device_id: deviceId }
  });

  if (!trusted) {
    // New device — require additional OTP verification
    await this.triggerDeviceVerification(userId, deviceId);
    throw new UnauthorizedException('NEW_DEVICE_VERIFICATION_REQUIRED');
  }

  // Verify fingerprint hasn't changed dramatically
  const similarity = this.calculateSimilarity(
    trusted.last_fingerprint, fingerprint
  );
  if (similarity < 0.7) {
    await this.flagFraud(userId, 'device_fingerprint_mismatch', 'medium', {});
  }
}
```

---

## 4. SSL Certificate Pinning (Flutter)

```dart
// mobile/lib/core/network/http_client.dart
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

class SecureHttpClient {
  static Dio createClient() {
    final dio = Dio();

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => false;

        // Load pinned certificate from assets
        client.findProxy = null;

        return client;
      },
    );

    // Certificate pinning via custom adapter
    dio.interceptors.add(CertificatePinningInterceptor(
      allowedSHAFingerprints: [
        'AA:BB:CC:DD:EE:FF:...',  // Production cert SHA-256
        'AA:BB:CC:DD:EE:FF:...',  // Backup cert SHA-256
      ],
    ));

    return dio;
  }
}
```

---

## 5. Root & Emulator Detection (Kotlin)

```kotlin
// android/app/src/main/kotlin/SecurityChecker.kt
class SecurityChecker(private val context: Context) {

    fun isDeviceCompromised(): Boolean {
        return isRooted() || isEmulator() || isDebuggable() || isTampered()
    }

    private fun isRooted(): Boolean {
        val rootIndicators = listOf(
            "/system/app/Superuser.apk",
            "/sbin/su", "/system/bin/su", "/system/xbin/su",
            "/data/local/xbin/su", "/data/local/bin/su"
        )
        return rootIndicators.any { File(it).exists() } ||
               canExecuteSu() ||
               checkBuildTags()
    }

    private fun isEmulator(): Boolean {
        return (Build.FINGERPRINT.startsWith("generic") ||
                Build.FINGERPRINT.startsWith("unknown") ||
                Build.MODEL.contains("google_sdk") ||
                Build.MODEL.contains("Emulator") ||
                Build.MODEL.contains("Android SDK built for x86") ||
                Build.MANUFACTURER.contains("Genymotion") ||
                Build.BRAND.startsWith("generic") ||
                Build.DEVICE.startsWith("generic") ||
                "google_sdk" == Build.PRODUCT)
    }

    private fun isTampered(): Boolean {
        // Verify APK signature matches expected
        val expectedSignature = "YOUR_RELEASE_SIGNATURE_HASH"
        val actualSignature = getApkSignature()
        return actualSignature != expectedSignature
    }

    private fun canExecuteSu(): Boolean {
        return try {
            Runtime.getRuntime().exec(arrayOf("/system/xbin/which", "su"))
            true
        } catch (e: Exception) {
            false
        }
    }
}
```

---

## 6. VPN/Proxy Detection

```typescript
// Server-side VPN detection
@Injectable()
export class VpnDetectionService {

  async isVpnDetected(ipAddress: string): Promise<boolean> {
    // Check against IP reputation APIs
    const [abuseIPDB, ipHub] = await Promise.all([
      this.checkAbuseIPDB(ipAddress),
      this.checkIPHub(ipAddress),
    ]);

    return abuseIPDB.isVpn || ipHub.block === 1;
  }

  async handleVpnUser(userId: string, ipAddress: string): Promise<void> {
    // Log but don't ban immediately (some users legitimately use VPN)
    await this.fraudService.logEvent(userId, 'vpn_detected', 'low', {
      ip: ipAddress,
    });

    // Flag for manual review if combined with other signals
    const fraudScore = await this.getFraudScore(userId);
    if (fraudScore > 70) {
      await this.suspendAccount(userId, 'high_fraud_score_with_vpn');
    }
  }
}
```

---

## 7. Multiple Account Detection

```typescript
@Injectable()
export class MultiAccountDetectionService {

  async detectOnRegistration(
    userId: string,
    deviceId: string,
    ipAddress: string,
  ): Promise<void> {
    // Check same device used before
    const deviceAccounts = await this.getAccountsByDevice(deviceId);
    if (deviceAccounts.length > 0) {
      await this.flagFraud(userId, 'multiple_accounts_same_device', 'high', {
        existing_accounts: deviceAccounts.map(u => u.id),
      });
    }

    // Check same IP range
    const subnet = this.getSubnet(ipAddress);  // /24 range
    const recentAccounts = await this.getRecentAccountsBySubnet(subnet, '1h');
    if (recentAccounts.length > 3) {
      await this.flagFraud(userId, 'mass_registration_from_subnet', 'medium', {
        subnet, count: recentAccounts.length,
      });
    }
  }
}
```

---

## 8. Game Integrity Validation

```typescript
// Server always validates ALL game moves
// Client cannot modify game state directly — only sends intent

// Every card in the game is tracked server-side
// Player hands are encrypted and stored in Redis
// All draws/discards verified against server state

export class GameIntegrityService {

  // Hash game state after each move for audit trail
  generateStateHash(state: GameState): string {
    const stateString = JSON.stringify({
      turn: state.turn_number,
      players: state.players.map(p => ({
        id: p.user_id,
        hand_size: p.hand.length,
        status: p.status,
      })),
      open_top: state.open_pile[0],
      closed_count: state.closed_pile.length,
    });

    return crypto.createHash('sha256').update(stateString).digest('hex');
  }

  // Full game replay audit for disputes
  async replayGame(matchId: string): Promise<GameAuditResult> {
    const rounds = await this.gameRoundRepo.find({
      where: { match_id: matchId },
      order: { timestamp: 'ASC' },
    });

    // Re-execute every move and verify final state matches recorded outcome
    const engine = new GameStateMachine();
    for (const round of rounds) {
      await engine.applyRound(round);
    }

    return engine.generateAuditReport();
  }
}
```

---

## 9. Secrets Management

```typescript
// Never hardcode secrets — use environment variables + AWS Secrets Manager

// In production, load from AWS Secrets Manager
const getSecrets = async () => {
  const client = new SecretsManagerClient({ region: 'ap-south-1' });
  const response = await client.send(
    new GetSecretValueCommand({ SecretId: 'rummy/production' })
  );
  return JSON.parse(response.SecretString);
};

// All secrets:
// - JWT_SECRET (rotate every 30 days)
// - DATABASE_URL
// - REDIS_URL
// - RAZORPAY_KEY_SECRET
// - FIREBASE_PRIVATE_KEY
// - ENCRYPTION_KEY (AES-256 for hand encryption)
```

---

## 10. Security Checklist

```
Authentication
  [x] JWT with 15-min expiry
  [x] Refresh token rotation with family tracking
  [x] Device binding
  [x] OTP for new device login
  [x] Account lockout after 5 failed attempts

Transport
  [x] TLS 1.3 everywhere
  [x] HSTS headers
  [x] Certificate pinning in mobile app
  [x] WSS for WebSockets

API Security
  [x] Rate limiting per endpoint
  [x] Input validation (class-validator)
  [x] Parameterized queries (TypeORM)
  [x] CORS whitelist
  [x] Helmet.js headers
  [x] No stack traces in production responses

Data Security
  [x] AES-256 encryption for game hands
  [x] PII encrypted at column level (phone, PAN)
  [x] DB encrypted at rest
  [x] Redis AUTH + TLS
  [x] Audit log for all sensitive operations

Mobile Security
  [x] Root detection
  [x] Emulator detection
  [x] APK signature verification
  [x] Obfuscation (ProGuard)
  [x] Secure storage (EncryptedSharedPreferences)
  [x] No secrets in APK

Game Security
  [x] Server-side validation for all moves
  [x] Cards dealt server-side only
  [x] Hands encrypted in Redis
  [x] Collusion detection
  [x] Replay audit system
```
