#!/usr/bin/env python3
"""Build Splunk Synthetics browser test JSON for Heathrow parking staging flow."""

import json
import os

JQ_GUARD = """function waitFor(fn, ms) {
  var end = Date.now() + ms;
  while (Date.now() < end) {
    var r = fn();
    if (r) return r;
  }
  return null;
}

var $ = waitFor(function () {
  return window.jQuery || window.$ || null;
}, 15000);

if (!$) {
  throw new Error("jQuery not loaded on " + window.location.pathname);
}
"""


def js_step(name, code, wait_for_nav=False, nav_timeout=50):
    # Splunk API max waitForNavTimeout is 20000 ms
    nav_timeout = min(nav_timeout, 20000)
    return {
        "name": name,
        "type": "run_javascript",
        "waitForNav": wait_for_nav,
        "waitForNavTimeout": nav_timeout,
        "waitForNavTimeoutDefault": False,
        "value": JQ_GUARD + code,
    }


def assert_css(name, selector, timeout=15000):
    return {
        "name": name,
        "type": "assert_element_present",
        "maxWaitTime": timeout,
        "maxWaitTimeDefault": False,
        "selectorType": "css",
        "selector": selector,
    }


def assert_text(name, text, timeout=10000):
    return {
        "name": name,
        "type": "assert_text_present",
        "maxWaitTime": timeout,
        "maxWaitTimeDefault": False,
        "value": text,
    }


def go_to(name, url):
    return {
        "name": name,
        "type": "go_to_url",
        "url": url,
        "action": "go_to_url",
        "options": {"url": url},
    }


def splunk_global_var(value: str) -> str:
    """Wrap a Splunk global variable name as {{env.name}} unless already wrapped."""
    value = value.strip()
    if value.startswith("{{") and value.endswith("}}"):
        return value
    return f"{{{{env.{value}}}}}"


def build_test():
    parking_url = os.environ.get(
        "PARKING_URL",
        "https://app-storefront.staging.lhr.aero/booking/parking",
    )
    checkout_url = os.environ.get(
        "CHECKOUT_URL",
        parking_url.replace("/booking/parking", "/booking/checkout"),
    )
    cart_url = os.environ.get(
        "CART_URL",
        parking_url.replace("/booking/parking", "/booking/cart"),
    )
    test_name = os.environ.get("TEST_NAME")
    if not test_name:
        raise SystemExit(
            "TEST_NAME is required. Example: export TEST_NAME='Heathrow Car Parking (Staging) T2 7 Day'"
        )
    frequency = int(os.environ.get("FREQUENCY", "60"))
    location_ids = [
        loc.strip()
        for loc in os.environ.get("LOCATION_IDS", "aws-eu-west-2").split(",")
        if loc.strip()
    ]
    auth_username = os.environ.get("AUTH_USERNAME")
    if not auth_username:
        raise SystemExit(
            "AUTH_USERNAME is required. Example: export AUTH_USERNAME='storefront'"
        )
    auth_password = os.environ.get("AUTH_PASSWORD")
    if not auth_password:
        raise SystemExit(
            "AUTH_PASSWORD is required. Example: export AUTH_PASSWORD='hw_parking_staging_password'"
        )
    auth_password = splunk_global_var(auth_password)
    active = os.environ.get("ACTIVE", "true").lower() not in ("0", "false", "no")
    device_id = int(os.environ.get("DEVICE_ID", "1"))

    enter_dates = """
function addDays(date, days) {
  var d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

var entry = addDays(new Date(), 28);
var exit = addDays(entry, 1);

$('#entryDate').datepicker('setDate', entry);
$('#entryDate').trigger('changeDate');

$('#exitDate').datepicker('setDate', exit);
$('#exitDate').trigger('changeDate');

return $('#entryDate').val();
"""

    enter_times = """
$('#entryTime').val('10:00').trigger('change').trigger('input');
$('#exitTime').val('18:00').trigger('change').trigger('input');
return { entryTime: $('#entryTime').val(), exitTime: $('#exitTime').val() };
"""

    select_terminal = """
var terminal = 'LHR2';
$('.terminal-button[data-val="' + terminal + '"]').trigger('click');
return {
  terminal: $('#terminal').val(),
  selectedButton: $('.terminal-button.selected').attr('data-val')
};
"""

    get_quote = """
$('#entryDate, #exitDate, #entryTime, #exitTime, #terminal').addClass('filled');
$('.button-booking .submit-form').removeAttr('disabled')[0].click();
return 'submitted';
"""

    show_options = """
var showBtn = waitFor(function () {
  var tile = $('.product-tile').filter(function () {
    return $(this).find('.product-tile-name').text().indexOf('Park & Ride Terminals 2') >= 0;
  }).first();
  if (!tile.length) return null;
  var btn = tile.find('.show-bundle-options[data-options-count]').first();
  return btn.length ? btn : null;
}, 30000);

if (!showBtn) throw new Error('Show options not ready for Park & Ride T2');

showBtn[0].click();

var pid = showBtn.data('pid');
var panel = waitFor(function () {
  var p = $('.bundle-section-wrapper[data-parking-pid="' + pid + '"]');
  return p.length && !p.hasClass('d-none') ? p : null;
}, 10000);

if (!panel) throw new Error('Bundle panel did not expand for pid ' + pid);
return 'opened';
"""

    book_parking = """
var tile = $('.product-tile').filter(function () {
  return $(this).find('.product-tile-name').text().indexOf('Park & Ride Terminals 2') >= 0;
}).first();
if (!tile.length) throw new Error('Park & Ride tile not found');

var pid = tile.find('.show-bundle-options').data('pid');
var panel = $('.bundle-section-wrapper[data-parking-pid="' + pid + '"]');
if (panel.hasClass('d-none')) {
  tile.find('.show-bundle-options[data-options-count]').first()[0].click();
}

var bookBtn = waitFor(function () {
  var p = $('.bundle-section-wrapper[data-parking-pid="' + pid + '"]');
  if (p.hasClass('d-none')) return null;
  var b = p.find('.bundle-card[data-bundle-group="parking"] .book-btn[data-bundle]').first();
  return b.length ? b : null;
}, 20000);

if (!bookBtn) throw new Error('Book button not found');

bookBtn[0].click();

waitFor(function () {
  var p = window.location.pathname;
  return p.indexOf('/booking/cart') >= 0 || p.indexOf('/booking/travel-extras') >= 0;
}, 15000);

return 'booked on ' + window.location.pathname;
"""

    # POST create expects deviceId (integer), not the read-only device object from GET.
    # Omit type ("browser") — it is read-only and rejected on create.
    return {
        "test": {
            "name": test_name,
            "active": active,
            "frequency": frequency,
            "schedulingStrategy": "round_robin",
            "locationIds": location_ids,
            "automaticRetries": 0,
            "deviceId": device_id,
            "advancedSettings": {
                "authentication": {
                    "username": auth_username,
                    "password": auth_password,
                },
                "verifyCertificates": True,
                "collectInteractiveMetrics": True,
                "excludedFiles": [{"type": "custom", "regex": "evgnet\\.com"}],
            },
            "transactions": [
                {
                    "name": "Home Page",
                    "steps": [go_to("Home Page", parking_url)],
                },
                {
                    "name": "Time and Dates",
                    "steps": [
                        js_step("Enter Dates", enter_dates),
                        js_step("Enter Times", enter_times),
                    ],
                },
                {
                    "name": "Terminal",
                    "steps": [js_step("Select Terminal", select_terminal)],
                },
                {
                    "name": "Quote",
                    "steps": [
                        js_step("Get a Quote", get_quote, wait_for_nav=True, nav_timeout=15000),
                        assert_text("Check For Results", "options available", 10000),
                        js_step("Show Options", show_options),
                        js_step("Book Parking", book_parking, wait_for_nav=True, nav_timeout=20000),
                        go_to("Go to Basket", cart_url),
                        assert_css("Assert Basket", 'a.checkout-btn[href="/booking/checkout"]', 20000),
                        go_to("Go to Checkout", checkout_url),
                        assert_css("Assert Checkout", '[data-checkout-stage="payment"]', 15000),
                    ],
                },
            ],
        }
    }


if __name__ == "__main__":
    print(json.dumps(build_test(), indent=2))
