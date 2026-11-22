// Effect logic ported from ETS2_PS5_Adaptive_Triggers.exe v1.5 (17.11.2026) by LikeARealG.
// Constants and ordering follow the Windows binary; see README "Differences".
#include "effects.h"
#include <math.h>

static inline void raise(uint8_t &v, uint8_t to) { if (v < to) v = to; }
static inline uint8_t u8(float f) { return (uint8_t)(int)f; }

void effects_prime(EffectState &s, const Telemetry &t) {
    s.prevFined = t.fined;
    s.prevGear = t.gear;
    s.prevEngineEnabled = t.engineEnabled;
    s.prevRpm = t.engineRpm;
    s.prevSpeed = t.speed;
}

Output effects_step(EffectState &s, const Telemetry &t, const Config &c, double now, Status *st) {
    Output o;
    Status local;
    Status &f = st ? *st : local;
    f = Status();

    float fuelPct = t.fuelCapacity > 0 ? t.fuel / t.fuelCapacity * 100.0f : 0;
    float kmh = t.speed * 3.6f;
    float accel = (t.speed - s.prevSpeed) / 0.0166f;
    f.fuelPct = fuelPct;
    f.speedKmh = kmh;
    f.accel = accel;

    if (!t.paused) {
        int frame = ++s.frame;

        // --- lightbar: fine alert overrides the status colours ---
        bool fineRunning = false;
        if (c.fineAlert) {
            if (t.fined != s.prevFined) {
                s.fineActive = true;
                s.fineStart = now;
            }
            fineRunning = s.fineActive;
        }
        if (fineRunning) {
            f.fine = true;
            float e = (float)(now - s.fineStart);
            if (e > 5.0f) {
                s.fineActive = false;
            } else {
                int phase = (int)(e * 4.0f) % 8;
                if (phase == 0 || phase == 2) o.r = 255;
                else if (phase == 4 || phase == 6) o.b = 255;
                if (frame % 20 < 10) raise(o.leftRumble, 200);
                else raise(o.rightRumble, 200);
            }
        } else if (c.parkBrakeLightbar && t.parkBrake) {
            o.r = 255;
        } else if (c.retarderLightbar && t.engineEnabled && t.retarderBrake != 0) {
            o.b = u8((sinf((float)frame * 0.1f * (float)t.retarderBrake) + 1.0f) * 0.5f * 255.0f);
        } else if (c.blinkersLightbar && t.engineEnabled) {
            if (t.blinkerLeftOn && t.blinkerRightOn) { o.r = 255; o.g = 255; }
            else if (t.blinkerLeftOn || t.blinkerRightOn) o.g = 255;
        }

        // --- mic LED master warning ---
        bool critical = t.oilPressureWarning || t.waterTemperatureWarning || t.airPressureWarning || t.wearChassis > 0.25f;
        bool minor = t.adblueWarning || t.batteryVoltageWarning;
        if (c.warningsMicLed) {
            if (critical) o.micLed = MIC_PULSE;
            else if (minor) o.micLed = MIC_ON;
        }

        // --- player LEDs fuel gauge ---
        if (c.fuelPlayerLeds) {
            float blinkBelow = -1;
            if (fuelPct > 80) { o.playerLeds = 0x1f; blinkBelow = 90; }
            else if (fuelPct > 60) { o.playerLeds = 0x1b; blinkBelow = 70; }
            else if (fuelPct > 40) { o.playerLeds = 0x15; blinkBelow = 50; }
            else if (fuelPct > 20) { o.playerLeds = 0x0a; blinkBelow = 30; }
            else if (fuelPct > 0.1f) { o.playerLeds = 0x04; blinkBelow = 10; }
            if (fuelPct < blinkBelow) o.playerBrightness = frame % 60 < 30 ? 0 : 2;
        }

        // --- refuel chug ---
        if (c.refuelRumble > 0 && t.refuel) {
            f.refuel = true;
            if ((frame & 15) < 8) {
                float p = fuelPct < 0 ? 0 : (fuelPct > 100 ? 100 : fuelPct);
                uint8_t v = u8(c.refuelRumble * (255.0f - p * 255.0f / 100.0f));
                raise(o.leftRumble, v);
                raise(o.rightRumble, v);
            }
        }

        // --- gear jolt: two frames, strong-left then strong-right ---
        if (c.gearJolt > 0) {
            uint8_t weak = u8(c.gearJolt * 100.0f), strong = u8(c.gearJolt * 255.0f);
            if (t.gear != s.prevGear && t.gear != 0 && s.prevGear != 0) {
                f.jolt = true;
                raise(o.leftRumble, strong);
                raise(o.rightRumble, weak);
                s.joltStage = 2;
            } else if (s.joltStage > 0) {
                f.jolt = true;
                raise(o.leftRumble, weak);
                raise(o.rightRumble, strong);
                s.joltStage = 0;
            }
        }

        // --- engine start: cranking kick (right) then lurch (left) ---
        if (c.engineStart > 0) {
            if (t.engineEnabled && !s.prevEngineEnabled) {
                s.lurchActive = true;
                s.lurchStart = now;
            }
            if (!t.engineEnabled && t.engineRpm > 0 && t.engineRpm >= s.prevRpm) {
                f.cranking = true;
                if (frame % 10 < 5) raise(o.rightRumble, u8(c.engineStart * 200.0f));
            }
            if (s.lurchActive) {
                f.lurch = true;
                float e = (float)(now - s.lurchStart);
                if (e >= 1.5f) s.lurchActive = false;
                else raise(o.leftRumble, u8(sinf(e / 1.5f * 3.1415927f) * 255.0f * c.engineStart));
            }
        }

        if (t.engineEnabled) {
            // --- hard braking, else body roll ---
            if (c.hardBraking > 0 && t.userBrake > 0.8f && kmh > 10.0f && accel < -10.0f) {
                f.brake = true;
                if (frame % 6 < 3) {
                    uint8_t v = u8(c.hardBraking * 255.0f);
                    raise(o.leftRumble, v);
                    raise(o.rightRumble, v);
                }
            } else if (c.bodyRoll > 0 && kmh > 10.0f) {
                double roll = t.rotationZ * 100.0;
                float a = (float)fabs(roll);
                if (a > 0.1f) {
                    f.roll = true;
                    if (a > 2.0f) a = 2.0f;
                    float intensity = (a - 0.1f) * 225.0f / 1.9f + 30.0f;
                    uint8_t v = u8((sinf((float)frame * 0.2f) + 1.0f) * 0.5f * intensity * c.bodyRoll);
                    if (roll <= 0.0) raise(o.rightRumble, v);
                    else raise(o.leftRumble, v);
                }
            }

            // --- brake trigger: resistance grows with speed, max at 90 km/h ---
            if (c.brakeTrigger > 0) {
                float k = kmh < 0 ? 0 : (kmh > 90.0f ? 90.0f : kmh);
                o.brakeTriggerOn = true;
                o.brakeForce = u8(k * 200.0f / 90.0f * c.brakeTrigger);
            }

            // --- throttle trigger: vibration frequency high when lugging or near the redline ---
            if (c.throttleTrigger > 0) {
                // Upstream derives these two thresholds once at startup; here they follow the current truck.
                float span = t.engineRpmMax - 550.0f;
                float low = span * 0.2f + 550.0f;
                float high = span * 0.7f + 550.0f;
                float rpm = t.engineRpm;
                float v;
                if (rpm > low) {
                    if (rpm < high || t.engineRpmMax == high) v = 0;
                    else {
                        float x = rpm < high ? high : rpm;
                        if (x > t.engineRpmMax) x = t.engineRpmMax;
                        v = (x - high) * 255.0f / (t.engineRpmMax - high);
                    }
                } else if (low == 550.0f) {
                    v = 200.0f;
                } else {
                    float x = rpm < 550.0f ? 550.0f : rpm;
                    if (x > low) x = low;
                    v = 200.0f - (x - 550.0f) * 200.0f / (low - 550.0f);
                }
                o.throttleTriggerOn = true;
                o.throttleFreq = u8(c.throttleTrigger * v);
            }
        }
    }

    s.prevSpeed = t.speed;
    s.prevEngineEnabled = t.engineEnabled;
    s.prevRpm = t.engineRpm;
    s.prevGear = t.gear;
    s.prevFined = t.fined;
    return o;
}

double rim_step(RimState &s, int x, int y, float speedMs, const Config &c) {
    const double PI2 = 6.283185307179586;
    double lock = (double)c.rimLockDegrees * PI2 / 360.0;
    double threshold = s.active ? 86.36 : 99.06;
    if ((double)(x * x + y * y) >= threshold * threshold) {
        double angle = atan2((double)x, (double)y);
        if (s.active) {
            double kmh = fabs((double)(speedMs * 3.6f));
            if (!isfinite(kmh)) kmh = 0;
            double ratio = kmh / (double)c.rimMaxDeviationSpeed;
            if (ratio > 1.0) ratio = 1.0;
            double delta = remainder(angle - s.prevAngle, PI2);
            s.steer += delta / (ratio * ((double)c.rimMaxDegreeDeviation - 1.0) + 1.0);
            if (s.steer > lock) s.steer = lock;
            if (s.steer < -lock) s.steer = -lock;
        }
        s.active = true;
        s.prevAngle = angle;
    } else {
        s.active = false;
    }
    return s.steer / lock;
}
