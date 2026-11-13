/*
 * Report the active layer to the host over Raw HID (zzeneg/zmk-raw-hid).
 *
 * Report layout (CONFIG_RAW_HID_REPORT_SIZE bytes, little endian):
 *   [0]    'L' (0x4C) magic
 *   [1]    protocol version (1)
 *   [2]    highest active layer index (position in the keymap)
 *   [3]    highest active layer id
 *   [4..7] layer state bitmask (by layer id)
 *   [8..]  layer display name, NUL terminated ("" when the layer has none)
 *
 * The host can ask for the current state by writing a report whose first
 * byte is 'L'. It does so when it opens the device, so a freshly started
 * host app does not have to wait for the next layer change.
 *
 * Sending happens on a dedicated work queue: the USB path blocks for up to
 * 30 ms waiting for the previous IN transfer, and that must not stall key
 * processing on the system work queue.
 */

#include <string.h>

#include <zephyr/kernel.h>
#include <zephyr/init.h>
#include <zephyr/sys/byteorder.h>

#include <zmk/event_manager.h>
#include <zmk/events/layer_state_changed.h>
#include <zmk/keymap.h>

#include <raw_hid/events.h>

#include <zephyr/logging/log.h>
LOG_MODULE_DECLARE(zmk, CONFIG_ZMK_LOG_LEVEL);

#define LAYER_REPORT_MAGIC 0x4C
#define LAYER_REPORT_VERSION 1
#define LAYER_REPORT_NAME_OFFSET 8

BUILD_ASSERT(CONFIG_RAW_HID_REPORT_SIZE > LAYER_REPORT_NAME_OFFSET + 1,
             "Raw HID report too small for the layer report");

/* Coalesces the burst of events a single &to or &tog produces. */
#define LAYER_REPORT_DEBOUNCE K_MSEC(5)

static K_THREAD_STACK_DEFINE(layer_report_stack, CONFIG_ZEN_LAYER_REPORT_STACK_SIZE);
static struct k_work_q layer_report_q;

static void layer_report_send(struct k_work *work) {
    /* Static: the raw_hid listeners copy it, but keep it off this small stack. */
    static uint8_t report[CONFIG_RAW_HID_REPORT_SIZE];

    zmk_keymap_layer_index_t index = zmk_keymap_highest_layer_active();
    zmk_keymap_layer_id_t id = zmk_keymap_layer_index_to_id(index);
    const char *name = zmk_keymap_layer_name(id);

    memset(report, 0, sizeof(report));
    report[0] = LAYER_REPORT_MAGIC;
    report[1] = LAYER_REPORT_VERSION;
    report[2] = index;
    report[3] = id;
    sys_put_le32(zmk_keymap_layer_state(), &report[4]);
    if (name != NULL) {
        /* Last byte stays 0, so the name is always terminated. */
        strncpy((char *)&report[LAYER_REPORT_NAME_OFFSET], name,
                sizeof(report) - LAYER_REPORT_NAME_OFFSET - 1);
    }

    LOG_DBG("Layer report: index %d id %d", index, id);
    raise_raw_hid_sent_event(
        (struct raw_hid_sent_event){.data = report, .length = sizeof(report)});
}

/* Defined statically so an event raised before init cannot hit a zeroed item. */
static K_WORK_DELAYABLE_DEFINE(layer_report_work, layer_report_send);

static void layer_report_schedule(k_timeout_t delay) {
    k_work_reschedule_for_queue(&layer_report_q, &layer_report_work, delay);
}

static int layer_report_listener(const zmk_event_t *eh) {
    if (as_zmk_layer_state_changed(eh) != NULL) {
        layer_report_schedule(LAYER_REPORT_DEBOUNCE);
        return ZMK_EV_EVENT_BUBBLE;
    }

    const struct raw_hid_received_event *rx = as_raw_hid_received_event(eh);
    if (rx != NULL && rx->length > 0 && rx->data[0] == LAYER_REPORT_MAGIC) {
        layer_report_schedule(K_NO_WAIT);
    }

    return ZMK_EV_EVENT_BUBBLE;
}

ZMK_LISTENER(zen_layer_report, layer_report_listener);
ZMK_SUBSCRIPTION(zen_layer_report, zmk_layer_state_changed);
ZMK_SUBSCRIPTION(zen_layer_report, raw_hid_received_event);

static int layer_report_init(void) {
    k_work_queue_start(&layer_report_q, layer_report_stack,
                       K_THREAD_STACK_SIZEOF(layer_report_stack),
                       CONFIG_ZEN_LAYER_REPORT_THREAD_PRIORITY,
                       &(struct k_work_queue_config){.name = "zen_layer_report"});
    return 0;
}

SYS_INIT(layer_report_init, APPLICATION, CONFIG_APPLICATION_INIT_PRIORITY);
