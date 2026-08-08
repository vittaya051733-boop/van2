const SETTLEMENT_DOC_PATH = 'platform_config/settlement';

const DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE = 0.15;
const DEFAULT_GP_RATE = 0.18;
const DEFAULT_LEADER_RATE = 0.15;
const DEFAULT_RIDER_CREDIT_DELAY_MINUTES = 120;
const DEFAULT_SHOP_CREDIT_DELAY_MINUTES = 120;

function readDouble(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const parsed = Number.parseFloat(value.trim());
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function readRatePercent(data, key, fallbackPercent) {
  const value = readDouble(data?.[key]);
  if (value == null || value < 0 || value > 100) {
    return fallbackPercent;
  }
  return value;
}

function readDelayMinutes(data, key, fallbackMinutes) {
  const value = readDouble(data?.[key]);
  if (value == null || value < 0) {
    return fallbackMinutes;
  }
  return Math.round(value);
}

function readSettlementConfigFromData(data) {
  const source = data && typeof data === 'object' ? data : {};
  return {
    gpRatePercent: readRatePercent(source, 'gpRatePercent', DEFAULT_GP_RATE * 100),
    riderPlatformRatePercent: readRatePercent(
      source,
      'riderPlatformRatePercent',
      DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE * 100,
    ),
    leaderRatePercent: readRatePercent(source, 'leaderRatePercent', DEFAULT_LEADER_RATE * 100),
    riderCreditDelayMinutes: readDelayMinutes(
      source,
      'riderCreditDelayMinutes',
      DEFAULT_RIDER_CREDIT_DELAY_MINUTES,
    ),
    shopCreditDelayMinutes: readDelayMinutes(
      source,
      'shopCreditDelayMinutes',
      DEFAULT_SHOP_CREDIT_DELAY_MINUTES,
    ),
  };
}

function createSettlementConfigLoader(deps) {
  const { db } = deps;

  async function loadSettlementConfig() {
    try {
      const snap = await db.doc(SETTLEMENT_DOC_PATH).get();
      return readSettlementConfigFromData(snap.data());
    } catch (_) {
      return readSettlementConfigFromData(null);
    }
  }

  function riderDeductionRate(config) {
    return (config?.riderPlatformRatePercent ?? DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE * 100) / 100;
  }

  function computeReleaseTimestamp(delayMinutes, Timestamp) {
    const safeMinutes =
      typeof delayMinutes === 'number' && delayMinutes >= 0
        ? delayMinutes
        : DEFAULT_RIDER_CREDIT_DELAY_MINUTES;
    const releaseAt = new Date(Date.now() + safeMinutes * 60 * 1000);
    return Timestamp.fromDate(releaseAt);
  }

  return {
    SETTLEMENT_DOC_PATH,
    DEFAULT_RIDER_CREDIT_DELAY_MINUTES,
    DEFAULT_SHOP_CREDIT_DELAY_MINUTES,
    readSettlementConfigFromData,
    loadSettlementConfig,
    riderDeductionRate,
    computeReleaseTimestamp,
  };
}

module.exports = {
  SETTLEMENT_DOC_PATH,
  DEFAULT_RIDER_PLATFORM_DEDUCTION_RATE,
  DEFAULT_GP_RATE,
  DEFAULT_LEADER_RATE,
  DEFAULT_RIDER_CREDIT_DELAY_MINUTES,
  DEFAULT_SHOP_CREDIT_DELAY_MINUTES,
  readSettlementConfigFromData,
  createSettlementConfigLoader,
};
