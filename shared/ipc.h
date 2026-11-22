// Shared-memory contract between the game plugin (x86_64, inside ETS2/ATS) and the app (arm64).
// Only fixed-width types in natural alignment order, so both architectures agree on the layout.
#pragma once
#include <stdint.h>
#include <time.h>

#define ETS2DS_TELEMETRY_PATH "/tmp/ets2_dualsense_telemetry_v2"
#define ETS2DS_STEERING_PATH "/tmp/ets2_dualsense_rimsteering_v2"
#define ETS2DS_MAGIC 0x45445332u
#define ETS2DS_MAX_WHEELS 8
#define ETS2DS_MAX_SUBSTANCES 32

enum { ETS2DS_GAME_UNKNOWN = 0, ETS2DS_GAME_ETS2 = 1, ETS2DS_GAME_ATS = 2 };

struct Telemetry {
    uint32_t magic;
    uint32_t seq;               // odd while the plugin is mid-copy
    uint64_t heartbeatMs;       // CLOCK_MONOTONIC ms of the last frame

    uint8_t sdkActive;
    uint8_t paused;
    uint8_t game;
    uint8_t engineEnabled;
    uint8_t electricEnabled;
    uint8_t parkBrake;
    uint8_t motorBrake;
    uint8_t cruiseControlOn;
    uint8_t airPressureWarning;
    uint8_t airPressureEmergency;
    uint8_t fuelWarning;
    uint8_t adblueWarning;
    uint8_t oilPressureWarning;
    uint8_t waterTemperatureWarning;
    uint8_t batteryVoltageWarning;
    uint8_t blinkerLeftOn;      // lamp state (flashes)
    uint8_t blinkerRightOn;
    uint8_t blinkerLeftActive;  // stalk state (steady)
    uint8_t blinkerRightActive;
    uint8_t hazardWarning;
    uint8_t lightLowBeam;
    uint8_t lightHighBeam;
    uint8_t lightBrake;
    uint8_t lightReverse;
    uint8_t lightBeacon;
    uint8_t wipers;
    uint8_t trailerConnected;
    uint8_t refuel;             // derived: fuel level rising
    uint8_t fined;              // toggles on every fine
    uint8_t tollgate;           // toggles on every toll payment
    uint8_t pad0[2];

    int32_t gear;
    int32_t displayedGear;
    uint32_t forwardGears;
    uint32_t retarderLevel;
    uint32_t retarderSteps;
    uint32_t wheelCount;

    float speed;                // m/s
    float cruiseControl;        // m/s, 0 = off
    float engineRpm;
    float engineRpmMax;
    float inputThrottle;
    float effectiveThrottle;
    float inputBrake;
    float effectiveBrake;
    float inputClutch;
    float effectiveClutch;
    float inputSteering;
    float fuel;
    float fuelCapacity;
    float airPressure;
    float brakeTemperature;
    float wearEngine;
    float wearTransmission;
    float wearCabin;
    float wearChassis;
    float wearWheels;
    float trailerWearChassis;
    float cargoDamage;
    float cargoMass;
    float accelX, accelY, accelZ;       // truck-local linear acceleration, m/s^2
    float angVelX, angVelY, angVelZ;    // truck-local angular velocity
    float fineAmount;
    float pad1;

    float wheelSuspDeflection[ETS2DS_MAX_WHEELS];
    float wheelAngularVelocity[ETS2DS_MAX_WHEELS]; // rotations per second
    float wheelRadius[ETS2DS_MAX_WHEELS];
    uint32_t wheelSubstance[ETS2DS_MAX_WHEELS];
    uint8_t wheelOnGround[ETS2DS_MAX_WHEELS];
    uint8_t wheelPowered[ETS2DS_MAX_WHEELS];
    uint8_t wheelSteerable[ETS2DS_MAX_WHEELS];

    double heading;             // world orientation, each 0..1 = full turn
    double pitch;
    double roll;

    char truckBrand[32];
    char truckName[64];
    char truckId[64];
    char substances[ETS2DS_MAX_SUBSTANCES][32];
};

static inline uint64_t ets2ds_now_ms(void) {
    return clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1000000ull;
}

// Steering word, same encoding as upstream: (ms << 21) | (round(steer * 1e6) + 1000000); 0 = not publishing.
static inline uint64_t ets2ds_steer_pack(double normalized) {
    long v = (long)(normalized * 1000000.0 + (normalized < 0 ? -0.5 : 0.5)) + 1000000;
    return (ets2ds_now_ms() << 21) | (uint64_t)v;
}
