const test = require('node:test');
const assert = require('node:assert/strict');
const {
  isOrderEligibleForRiderMatch,
} = require('./pending_order_rider_match');

test('shop order awaiting rider with notify ready is eligible', () => {
  assert.equal(
    isOrderEligibleForRiderMatch({
      status: 'awaiting_rider',
      driverId: null,
      riderNotifyReady: true,
      customerConfirmed: true,
      paymentStatus: 'cash_on_delivery',
    }),
    true,
  );
});

test('travel order awaiting rider with verified payment is eligible', () => {
  assert.equal(
    isOrderEligibleForRiderMatch({
      status: 'awaiting_rider',
      orderType: 'travel_passenger',
      riderNotifyReady: false,
      customerConfirmed: true,
      paymentStatus: 'verified',
    }),
    true,
  );
});

test('assigned or terminal orders are not eligible', () => {
  assert.equal(
    isOrderEligibleForRiderMatch({
      status: 'awaiting_rider',
      driverId: 'rider-1',
      riderNotifyReady: true,
      customerConfirmed: true,
    }),
    false,
  );
  assert.equal(
    isOrderEligibleForRiderMatch({
      status: 'cancelled',
      riderNotifyReady: true,
      customerConfirmed: true,
    }),
    false,
  );
});

test('awaiting slip review orders stay ineligible', () => {
  assert.equal(
    isOrderEligibleForRiderMatch({
      status: 'awaiting_rider',
      riderNotifyReady: true,
      customerConfirmed: true,
      paymentStatus: 'awaiting_slip_review',
    }),
    false,
  );
});
