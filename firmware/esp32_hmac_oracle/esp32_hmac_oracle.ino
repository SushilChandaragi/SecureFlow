#include <Arduino.h>
#include <mbedtls/md.h>

// Onboard LED pin (usually pin 2 on ESP32 DevKit modules, adjust if needed)
#define LED_PIN 2

// Baud rate for serial communication
#define BAUD_RATE 115200

// HMAC parameters
#define NONCE_SIZE 32
#define HMAC_SIZE 32

// High-entropy default shared secret burned in flash (matches mock_hardware_secret.txt)
const char* SHARED_SECRET = "SecureFlow-Mock-Secret-Change-Me-Use-High-Entropy";

// Buffer for holding the incoming 32-byte challenge nonce
uint8_t nonceBuffer[NONCE_SIZE];
size_t bytesRead = 0;
unsigned long lastByteTime = 0;

void blinkLED(int times, int delayMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(LED_PIN, HIGH);
    delay(delayMs);
    digitalWrite(LED_PIN, LOW);
    if (i < times - 1) {
      delay(delayMs);
    }
  }
}

void setup() {
  // Initialize GPIO for onboard LED
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  // Initialize Serial port
  Serial.begin(BAUD_RATE);
  
  // Wait for serial connection to stabilize
  while (!Serial) {
    delay(10);
  }

  // Signal boot complete and ready
  blinkLED(3, 100);
  digitalWrite(LED_PIN, HIGH); // Turn LED ON to signal idle/ready state
}

void loop() {
  unsigned long currentMillis = millis();

  // Transaction timeout guard:
  // If we have read some bytes, but 1000ms passes without completing the transaction,
  // reset the buffer to prevent synchronization lockups (e.g. from static or bad port noise).
  if (bytesRead > 0 && (currentMillis - lastByteTime > 1000)) {
    bytesRead = 0;
    // Rapidly flash LED to indicate a transaction timeout/corruption
    blinkLED(5, 50);
    digitalWrite(LED_PIN, HIGH); // Restore solid idle indicator
  }

  // Read available serial data
  while (Serial.available() > 0 && bytesRead < NONCE_SIZE) {
    nonceBuffer[bytesRead] = Serial.read();
    bytesRead++;
    lastByteTime = millis();
  }

  // Once we receive exactly 32 bytes, compute and return the HMAC
  if (bytesRead == NONCE_SIZE) {
    // Fast blink built-in LED to indicate cryptographic activity
    digitalWrite(LED_PIN, LOW);
    
    uint8_t hmacResult[HMAC_SIZE];
    
    // Set up mbedtls MD context for HMAC-SHA256
    mbedtls_md_context_t ctx;
    mbedtls_md_type_t md_type = MBEDTLS_MD_SHA256;
    
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(md_type), 1); // 1 = enable HMAC
    mbedtls_md_hmac_starts(&ctx, (const unsigned char*)SHARED_SECRET, strlen(SHARED_SECRET));
    mbedtls_md_hmac_update(&ctx, nonceBuffer, NONCE_SIZE);
    mbedtls_md_hmac_finish(&ctx, hmacResult);
    mbedtls_md_free(&ctx);
    
    // Return exactly 32 bytes back to the Python client
    Serial.write(hmacResult, HMAC_SIZE);
    Serial.flush();
    
    // Reset state for the next handshake
    bytesRead = 0;
    
    // Re-enable solid LED indicating ready/idle status
    digitalWrite(LED_PIN, HIGH);
  }
}
