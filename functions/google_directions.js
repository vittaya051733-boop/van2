async function fetchGoogleDrivingDirectionsRoute({
  apiKey,
  originLatitude,
  originLongitude,
  destinationLatitude,
  destinationLongitude,
  logger,
}) {
  const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
  url.searchParams.set('origin', `${originLatitude},${originLongitude}`);
  url.searchParams.set(
    'destination',
    `${destinationLatitude},${destinationLongitude}`,
  );
  url.searchParams.set('mode', 'driving');
  url.searchParams.set('language', 'th');
  url.searchParams.set('region', 'th');
  url.searchParams.set('key', apiKey);

  let response;
  try {
    response = await fetch(url);
  } catch (error) {
    logger?.error?.('fetchGoogleDrivingDirectionsRoute network failed', {
      message: error instanceof Error ? error.message : String(error),
    });
    return {
      ok: false,
      status: 'NETWORK_ERROR',
      errorMessage: 'network failed',
    };
  }

  const payload = await response.json().catch(() => null);
  const status = String(payload?.status || '').trim();
  if (!response.ok || status !== 'OK') {
    logger?.warn?.('fetchGoogleDrivingDirectionsRoute google response not OK', {
      httpStatus: response.status,
      googleStatus: status,
      errorMessage: payload?.error_message,
    });
    return {
      ok: false,
      status: status || String(response.status),
      errorMessage: String(payload?.error_message || '').trim(),
    };
  }

  const route = Array.isArray(payload?.routes) ? payload.routes[0] : null;
  const leg = Array.isArray(route?.legs) ? route.legs[0] : null;
  const encodedPolyline = String(route?.overview_polyline?.points || '').trim();
  const distanceMeters = Number(leg?.distance?.value || 0);
  const durationSeconds = Number(leg?.duration?.value || 0);

  if (!encodedPolyline || !Number.isFinite(distanceMeters) || distanceMeters <= 0) {
    return {
      ok: false,
      status: 'NO_ROUTE',
      errorMessage: 'missing route geometry',
    };
  }

  return {
    ok: true,
    distanceMeters: Math.round(distanceMeters),
    durationSeconds: Math.max(0, Math.round(durationSeconds)),
    encodedPolyline,
    provider: 'google_directions',
  };
}

module.exports = {
  fetchGoogleDrivingDirectionsRoute,
};
