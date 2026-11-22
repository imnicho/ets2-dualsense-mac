#pragma once
#include <stdint.h>
#include "../shared/ipc.h"

struct Config {
    bool rimSteering = false;
    float rimLockDegrees = 450;
    float rimMaxDegreeDeviation = 5;
    float rimMaxDeviationSpeed = 90;
    bool fineAlert = true;
    bool parkBrakeLightbar = true;
    bool retarderLightbar = true;
    bool blinkersLightbar = true;
    bool warningsMicLed = true;
    bool fuelPlayerLeds = true;
    float refuelRumble = 1;
    float gearJolt = 1;
    float engineStart = 1;
    float hardBraking = 1;
    float bodyRoll = 1;
    float brakeTrigger = 1;
    float throttleTrigger = 1;
};

enum MicLed : uint8_t { MIC_OFF = 0, MIC_ON = 1, MIC_PULSE = 2 };

// Mirrors the DS5W output state the Windows app fills in each frame.
struct Output {
    uint8_t leftRumble = 0;
    uint8_t rightRumble = 0;
    uint8_t micLed = MIC_OFF;
    uint8_t playerLeds = 0;
    uint8_t playerBrightness = 0;  // 0 = high, 2 = low
    uint8_t r = 0, g = 0, b = 0;
    bool brakeTriggerOn = false;   // left trigger: continuous resistance from position 0
    uint8_t brakeForce = 0;
    bool throttleTriggerOn = false; // right trigger: DS5W "EffectEx", forces 0, keepEffect
    uint8_t throttleFreq = 0;
};

struct Status {
    bool fine = false, jolt = false, cranking = false, lurch = false;
    bool brake = false, roll = false, refuel = false;
    float fuelPct = 0, speedKmh = 0, accel = 0;
};

struct EffectState {
    int frame = 0;
    bool fineActive = false;
    double fineStart = 0;
    uint8_t prevFined = 0;
    int joltStage = 0;
    int prevGear = 0;
    bool lurchActive = false;
    double lurchStart = 0;
    uint8_t prevEngineEnabled = 0;
    float prevRpm = 0;
    float prevSpeed = 0;
};

// Seeds the "previous" values so connecting mid-drive doesn't fire spurious events.
void effects_prime(EffectState &s, const Telemetry &t);

// One 16 ms frame. `now` is monotonic seconds.
Output effects_step(EffectState &s, const Telemetry &t, const Config &c, double now, Status *status);

// Rim steering: one stick sample (x right-positive, y up-positive, -128..127).
struct RimState {
    bool active = false;
    double prevAngle = 0;
    double steer = 0; // radians, clamped to +-lock
};
// Returns normalized steering in [-1, 1].
double rim_step(RimState &s, int x, int y, float speedMs, const Config &c);
