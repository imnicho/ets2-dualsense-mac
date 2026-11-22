// ETS2 DualSense (macOS) game plugin: publishes telemetry to a mapped file and
// registers the "DualSense Rim Steering" input device.
#include <atomic>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "scssdk_telemetry.h"
#include "scssdk_input.h"
#include "eurotrucks2/scssdk_eut2.h"
#include "eurotrucks2/scssdk_telemetry_eut2.h"
#include "eurotrucks2/scssdk_input_eut2.h"
#include "amtrucks/scssdk_ats.h"

#include "../shared/ipc.h"

static Telemetry *shared = nullptr; // mapped file, read by the app
static Telemetry cur;               // written by SDK callbacks, copied out once per frame

static void *map_file(const char *path, size_t size, bool create) {
    int fd = open(path, create ? (O_RDWR | O_CREAT) : O_RDWR, 0666);
    if (fd < 0) return nullptr;
    if (create) {
        fchmod(fd, 0666);
        if (ftruncate(fd, (off_t)size) != 0) { close(fd); return nullptr; }
    } else {
        struct stat st;
        if (fstat(fd, &st) != 0 || (size_t)st.st_size < size) { close(fd); return nullptr; }
    }
    void *p = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    return p == MAP_FAILED ? nullptr : p;
}

static void publish() {
    std::atomic<uint32_t> *seq = reinterpret_cast<std::atomic<uint32_t> *>(&shared->seq);
    uint32_t s = seq->load(std::memory_order_relaxed);
    seq->store(s + 1, std::memory_order_release);
    cur.seq = s + 1;
    memcpy(shared, &cur, sizeof(Telemetry));
    seq->store(s + 2, std::memory_order_release);
}

// ---- telemetry ----

SCSAPI_VOID store_bool(const scs_string_t, const scs_u32_t, const scs_value_t *const value, const scs_context_t ctx) {
    *static_cast<uint8_t *>(ctx) = value->value_bool.value ? 1 : 0;
}
SCSAPI_VOID store_float(const scs_string_t, const scs_u32_t, const scs_value_t *const value, const scs_context_t ctx) {
    *static_cast<float *>(ctx) = value->value_float.value;
}
SCSAPI_VOID store_s32(const scs_string_t, const scs_u32_t, const scs_value_t *const value, const scs_context_t ctx) {
    *static_cast<int32_t *>(ctx) = value->value_s32.value;
}
SCSAPI_VOID store_u32(const scs_string_t, const scs_u32_t, const scs_value_t *const value, const scs_context_t ctx) {
    *static_cast<uint32_t *>(ctx) = value->value_u32.value;
}
SCSAPI_VOID store_fvector(const scs_string_t, const scs_u32_t, const scs_value_t *const value, const scs_context_t ctx) {
    float *out = static_cast<float *>(ctx);
    out[0] = value->value_fvector.x;
    out[1] = value->value_fvector.y;
    out[2] = value->value_fvector.z;
}
SCSAPI_VOID store_placement(const scs_string_t, const scs_u32_t, const scs_value_t *const value, const scs_context_t) {
    cur.heading = value->value_dplacement.orientation.heading;
    cur.pitch = value->value_dplacement.orientation.pitch;
    cur.roll = value->value_dplacement.orientation.roll;
}

// Refuel detection, same heuristic as RenCloud's scs-telemetry (rev 12) which upstream ships.
static float last_fuel = 0;
static int fuel_ticker = 0, fuel_ticker2 = 0;

SCSAPI_VOID on_frame_end(const scs_event_t, const void *const, const scs_context_t) {
    float fuel = cur.fuel;
    if (fuel > last_fuel && last_fuel > 0) {
        fuel_ticker2 = 0;
        cur.refuel = 1;
    } else if (fuel < last_fuel) {
        fuel_ticker2 = 0;
        cur.refuel = 0;
    }
    if (fuel_ticker > 10) {
        fuel_ticker = 0;
        if (fuel == last_fuel) fuel_ticker2++; else fuel_ticker2 = 0;
        if (fuel_ticker2 >= 5) { fuel_ticker2 = 0; cur.refuel = 0; }
    }
    fuel_ticker++;
    last_fuel = fuel;
    cur.heartbeatMs = ets2ds_now_ms();
    publish();
}

SCSAPI_VOID on_pause(const scs_event_t event, const void *const, const scs_context_t) {
    cur.paused = event == SCS_TELEMETRY_EVENT_paused;
    cur.heartbeatMs = ets2ds_now_ms();
    publish();
}

static void copy_string(char *dst, size_t size, const scs_named_value_t *a) {
    if (a->value.type != SCS_VALUE_TYPE_string || !a->value.value_string.value) return;
    strncpy(dst, a->value.value_string.value, size - 1);
    dst[size - 1] = 0;
}

SCSAPI_VOID on_config(const scs_event_t, const void *const event_info, const scs_context_t) {
    const auto *info = static_cast<const scs_telemetry_configuration_t *>(event_info);
    if (strcmp(info->id, SCS_TELEMETRY_CONFIG_truck) == 0) {
        cur.truckBrand[0] = cur.truckName[0] = cur.truckId[0] = 0;
        for (const scs_named_value_t *a = info->attributes; a->name; ++a) {
            const char *n = a->name;
            scs_u32_t i = a->index;
            if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_brand)) copy_string(cur.truckBrand, sizeof(cur.truckBrand), a);
            else if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_name)) copy_string(cur.truckName, sizeof(cur.truckName), a);
            else if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_id)) copy_string(cur.truckId, sizeof(cur.truckId), a);
            else if (a->value.type == SCS_VALUE_TYPE_float) {
                float v = a->value.value_float.value;
                if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_fuel_capacity)) cur.fuelCapacity = v;
                else if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_rpm_limit)) cur.engineRpmMax = v;
                else if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_wheel_radius) && i < ETS2DS_MAX_WHEELS) cur.wheelRadius[i] = v;
            } else if (a->value.type == SCS_VALUE_TYPE_u32) {
                uint32_t v = a->value.value_u32.value;
                if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_forward_gear_count)) cur.forwardGears = v;
                else if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_retarder_step_count)) cur.retarderSteps = v;
                else if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_wheel_count)) cur.wheelCount = v;
            } else if (a->value.type == SCS_VALUE_TYPE_bool && i < ETS2DS_MAX_WHEELS) {
                uint8_t v = a->value.value_bool.value ? 1 : 0;
                if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_wheel_powered)) cur.wheelPowered[i] = v;
                else if (!strcmp(n, SCS_TELEMETRY_CONFIG_ATTRIBUTE_wheel_steerable)) cur.wheelSteerable[i] = v;
            }
        }
    } else if (strcmp(info->id, SCS_TELEMETRY_CONFIG_substances) == 0) {
        for (const scs_named_value_t *a = info->attributes; a->name; ++a)
            if (!strcmp(a->name, SCS_TELEMETRY_CONFIG_ATTRIBUTE_id) && a->index < ETS2DS_MAX_SUBSTANCES)
                copy_string(cur.substances[a->index], sizeof(cur.substances[0]), a);
    } else if (strcmp(info->id, SCS_TELEMETRY_CONFIG_job) == 0) {
        cur.cargoMass = 0;
        for (const scs_named_value_t *a = info->attributes; a->name; ++a)
            if (!strcmp(a->name, SCS_TELEMETRY_CONFIG_ATTRIBUTE_cargo_mass) && a->value.type == SCS_VALUE_TYPE_float)
                cur.cargoMass = a->value.value_float.value;
    }
}

SCSAPI_VOID on_gameplay(const scs_event_t, const void *const event_info, const scs_context_t) {
    const auto *info = static_cast<const scs_telemetry_gameplay_event_t *>(event_info);
    if (strcmp(info->id, SCS_TELEMETRY_GAMEPLAY_EVENT_player_fined) == 0) {
        cur.fined ^= 1;
        for (const scs_named_value_t *a = info->attributes; a->name; ++a)
            if (!strcmp(a->name, SCS_TELEMETRY_GAMEPLAY_EVENT_ATTRIBUTE_fine_amount) && a->value.type == SCS_VALUE_TYPE_s64)
                cur.fineAmount = (float)a->value.value_s64.value;
    } else if (strcmp(info->id, SCS_TELEMETRY_GAMEPLAY_EVENT_player_tollgate_paid) == 0) {
        cur.tollgate ^= 1;
    }
}

SCSAPI_RESULT scs_telemetry_init(const scs_u32_t version, const scs_telemetry_init_params_t *const params) {
    if (version != SCS_TELEMETRY_VERSION_1_01) return SCS_RESULT_unsupported;
    const auto *p = static_cast<const scs_telemetry_init_params_v101_t *>(params);

    shared = static_cast<Telemetry *>(map_file(ETS2DS_TELEMETRY_PATH, sizeof(Telemetry), true));
    if (!shared) {
        p->common.log(SCS_LOG_TYPE_error, "[ets2-dualsense] could not map " ETS2DS_TELEMETRY_PATH);
        return SCS_RESULT_generic_error;
    }
    uint32_t seq = shared->magic == ETS2DS_MAGIC ? (shared->seq | 1) + 1 : 0;
    memset(&cur, 0, sizeof(cur));
    cur.magic = ETS2DS_MAGIC;
    cur.paused = 1;
    cur.sdkActive = 1;
    if (!strcmp(p->common.game_id, SCS_GAME_ID_EUT2)) cur.game = ETS2DS_GAME_ETS2;
    else if (!strcmp(p->common.game_id, SCS_GAME_ID_ATS)) cur.game = ETS2DS_GAME_ATS;
    cur.heartbeatMs = ets2ds_now_ms();
    shared->seq = seq;

    p->register_for_event(SCS_TELEMETRY_EVENT_frame_end, on_frame_end, nullptr);
    p->register_for_event(SCS_TELEMETRY_EVENT_paused, on_pause, nullptr);
    p->register_for_event(SCS_TELEMETRY_EVENT_started, on_pause, nullptr);
    p->register_for_event(SCS_TELEMETRY_EVENT_configuration, on_config, nullptr);
    p->register_for_event(SCS_TELEMETRY_EVENT_gameplay, on_gameplay, nullptr);

#define CH(name, type, fn, to) \
    p->register_for_channel(SCS_TELEMETRY_TRUCK_CHANNEL_##name, SCS_U32_NIL, SCS_VALUE_TYPE_##type, SCS_TELEMETRY_CHANNEL_FLAG_none, fn, &cur.to)
    CH(speed, float, store_float, speed);
    CH(cruise_control, float, store_float, cruiseControl);
    CH(engine_rpm, float, store_float, engineRpm);
    CH(engine_gear, s32, store_s32, gear);
    CH(displayed_gear, s32, store_s32, displayedGear);
    CH(input_throttle, float, store_float, inputThrottle);
    CH(effective_throttle, float, store_float, effectiveThrottle);
    CH(input_brake, float, store_float, inputBrake);
    CH(effective_brake, float, store_float, effectiveBrake);
    CH(input_clutch, float, store_float, inputClutch);
    CH(effective_clutch, float, store_float, effectiveClutch);
    CH(input_steering, float, store_float, inputSteering);
    CH(fuel, float, store_float, fuel);
    CH(brake_air_pressure, float, store_float, airPressure);
    CH(brake_temperature, float, store_float, brakeTemperature);
    CH(wear_engine, float, store_float, wearEngine);
    CH(wear_transmission, float, store_float, wearTransmission);
    CH(wear_cabin, float, store_float, wearCabin);
    CH(wear_chassis, float, store_float, wearChassis);
    CH(wear_wheels, float, store_float, wearWheels);
    CH(retarder_level, u32, store_u32, retarderLevel);
    CH(local_linear_acceleration, fvector, store_fvector, accelX);
    CH(local_angular_velocity, fvector, store_fvector, angVelX);
    CH(world_placement, dplacement, store_placement, heading);
    CH(parking_brake, bool, store_bool, parkBrake);
    CH(motor_brake, bool, store_bool, motorBrake);
    CH(engine_enabled, bool, store_bool, engineEnabled);
    CH(electric_enabled, bool, store_bool, electricEnabled);
    CH(light_lblinker, bool, store_bool, blinkerLeftOn);
    CH(light_rblinker, bool, store_bool, blinkerRightOn);
    CH(lblinker, bool, store_bool, blinkerLeftActive);
    CH(rblinker, bool, store_bool, blinkerRightActive);
    CH(hazard_warning, bool, store_bool, hazardWarning);
    CH(light_low_beam, bool, store_bool, lightLowBeam);
    CH(light_high_beam, bool, store_bool, lightHighBeam);
    CH(light_brake, bool, store_bool, lightBrake);
    CH(light_reverse, bool, store_bool, lightReverse);
    CH(light_beacon, bool, store_bool, lightBeacon);
    CH(wipers, bool, store_bool, wipers);
    CH(brake_air_pressure_warning, bool, store_bool, airPressureWarning);
    CH(brake_air_pressure_emergency, bool, store_bool, airPressureEmergency);
    CH(fuel_warning, bool, store_bool, fuelWarning);
    CH(adblue_warning, bool, store_bool, adblueWarning);
    CH(oil_pressure_warning, bool, store_bool, oilPressureWarning);
    CH(water_temperature_warning, bool, store_bool, waterTemperatureWarning);
    CH(battery_voltage_warning, bool, store_bool, batteryVoltageWarning);
#undef CH
#define WCH(name, type, fn, to) \
    p->register_for_channel(SCS_TELEMETRY_TRUCK_CHANNEL_##name, i, SCS_VALUE_TYPE_##type, SCS_TELEMETRY_CHANNEL_FLAG_none, fn, &cur.to[i])
    for (scs_u32_t i = 0; i < ETS2DS_MAX_WHEELS; ++i) {
        WCH(wheel_susp_deflection, float, store_float, wheelSuspDeflection);
        WCH(wheel_velocity, float, store_float, wheelAngularVelocity);
        WCH(wheel_substance, u32, store_u32, wheelSubstance);
        WCH(wheel_on_ground, bool, store_bool, wheelOnGround);
    }
#undef WCH
    p->register_for_channel(SCS_TELEMETRY_TRAILER_CHANNEL_connected, SCS_U32_NIL, SCS_VALUE_TYPE_bool, SCS_TELEMETRY_CHANNEL_FLAG_none, store_bool, &cur.trailerConnected);
    p->register_for_channel(SCS_TELEMETRY_TRAILER_CHANNEL_cargo_damage, SCS_U32_NIL, SCS_VALUE_TYPE_float, SCS_TELEMETRY_CHANNEL_FLAG_none, store_float, &cur.cargoDamage);
    p->register_for_channel(SCS_TELEMETRY_TRAILER_CHANNEL_wear_chassis, SCS_U32_NIL, SCS_VALUE_TYPE_float, SCS_TELEMETRY_CHANNEL_FLAG_none, store_float, &cur.trailerWearChassis);

    publish();
    p->common.log(SCS_LOG_TYPE_message, "[ets2-dualsense] telemetry ready");
    return SCS_RESULT_ok;
}

SCSAPI_VOID scs_telemetry_shutdown(void) {
    if (shared) {
        cur.sdkActive = 0;
        publish();
        munmap(shared, sizeof(Telemetry));
    }
    shared = nullptr;
}

// ---- rim steering input device ----

static std::atomic<uint64_t> *steer = nullptr;
static uint64_t next_steer_open_ms = 0;

SCSAPI_RESULT steering_event(scs_input_event_t *const event_info, const scs_u32_t flags, const scs_context_t) {
    if (!(flags & SCS_INPUT_EVENT_CALLBACK_FLAG_first_in_frame)) return SCS_RESULT_not_found;
    event_info->input_index = 0;
    event_info->value_float.value = 0;

    uint64_t now = ets2ds_now_ms();
    if (!steer) {
        if (now < next_steer_open_ms) return SCS_RESULT_ok;
        next_steer_open_ms = now + 500;
        steer = static_cast<std::atomic<uint64_t> *>(map_file(ETS2DS_STEERING_PATH, 8, false));
        if (!steer) return SCS_RESULT_ok;
    }
    uint64_t w = steer->load();
    uint32_t v = (uint32_t)w & 0x1fffff;
    if (w != 0 && now - (w >> 21) < 1000 && v <= 2000000)
        event_info->value_float.value = (float)((int)v - 1000000) / 1000000.0f;
    return SCS_RESULT_ok;
}

SCSAPI_RESULT scs_input_init(const scs_u32_t version, const scs_input_init_params_t *const params) {
    if (version != SCS_INPUT_VERSION_1_00) return SCS_RESULT_unsupported;
    const auto *p = static_cast<const scs_input_init_params_v100_t *>(params);

    static const scs_input_device_input_t inputs[] = {{"steering", "Rim Steering Axis", SCS_VALUE_TYPE_float, 0}};
    scs_input_device_t dev;
    memset(&dev, 0, sizeof(dev));
    dev.name = "dualsense_rim";
    dev.display_name = "DualSense Rim Steering";
    dev.type = SCS_INPUT_DEVICE_TYPE_generic;
    dev.input_count = 1;
    dev.inputs = inputs;
    dev.input_event_callback = steering_event;
    return p->register_device(&dev);
}

SCSAPI_VOID scs_input_shutdown(void) {
    if (steer) munmap(steer, 8);
    steer = nullptr;
    next_steer_open_ms = 0;
}
