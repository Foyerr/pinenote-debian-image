#!/usr/bin/env bash
echo device >/sys/kernel/debug/usb/fcc00000.usb/mode # set usb to device mode 
sleep 0.25

# tablet-to-host HID forwarder for the PineNote
set -euo pipefail

CFG=/sys/kernel/config/usb_gadget
G=$CFG/g1
UDC=$(ls /sys/class/udc | head -n1)       # pick first controller

cleanup() {
    [[ -e $G/UDC ]] && echo "" >"$G/UDC" || true         # detach
    find "$G"/configs -type l -delete 2>/dev/null || true
    find "$G" -depth -type d -exec rmdir {} + 2>/dev/null || true    
}
trap cleanup EXIT SIGINT

##############################################################################
# fresh gadget
##############################################################################
cleanup
mkdir -p "$G" && cd "$G"

echo 0x1d6b > idVendor          # Linux Foundation
echo 0x0104 > idProduct         # Multifunction Composite Gadget
echo 0x0100 > bcdDevice         # v1.0.0
echo 0x0200 > bcdUSB            # USB 2.0

# -- strings -----------------------------------------------------------------
mkdir -p strings/0x409
echo "fedcba9876543210" > strings/0x409/serialnumber
echo "Pine64"           > strings/0x409/manufacturer
echo "PineNote"         > strings/0x409/product

# -- configuration -----------------------------------------------------------
mkdir -p configs/c.1/strings/0x409
echo "Conf 1" > configs/c.1/strings/0x409/configuration
echo 250      > configs/c.1/MaxPower           # mA

# -- HID function ------------------------------------------------------------
mkdir -p functions/hid.usb0
echo 2  > functions/hid.usb0/protocol          # mouse/pen-style
echo 1  > functions/hid.usb0/subclass
echo 15 > functions/hid.usb0/report_length

cat /sys/bus/hid/devices/0018:2D1F:0095.0001/report_descriptor \
      > functions/hid.usb0/report_desc
ln -s functions/hid.usb0 configs/c.1/

##############################################################################
# bind & discover our /dev/hidgN
##############################################################################
# Toying around with the idea of mutiple gadgets running at once via a usb hub, but not having much luck
# USB hub would run in host mode to work, maybe I need to find the other USB things to set them to device mode
PRE_HIDG=$(ls /dev/hidg* 2>/dev/null | sort || true)   # snapshot
echo "$UDC" > UDC                                      # bind

# wait up to 2 s for a new hidg node
for _ in {1..20}; do
    CUR_HIDG=$(ls /dev/hidg* 2>/dev/null | sort || true)
    NEW_HIDG=$(comm -13 <(printf '%s\n' "$PRE_HIDG") \
                     <(printf '%s\n' "$CUR_HIDG") | head -n1)
    [[ -n "$NEW_HIDG" ]] && break
    sleep 0.1
done
[[ -n "$NEW_HIDG" ]] || { echo "hidg device not found"; exit 1; }

##############################################################################
# forward tablet HID packets to the host
##############################################################################
stdbuf -oL cat /dev/hidraw0 | tee "$NEW_HIDG" >/dev/null
