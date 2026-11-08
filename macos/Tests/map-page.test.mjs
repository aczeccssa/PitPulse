import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';

const html = readFileSync(new URL('../Features/Maps/map.html', import.meta.url), 'utf8');
const script = html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
function page() {
  const elements = new globalThis.Map();
  const calls = [];
  const document = { getElementById(id) { if (!elements.has(id)) elements.set(id, { setAttribute() {} }); return elements.get(id); }, createElement() { return { setAttribute() {} }; } };
  let map, now = 0, rafID = 0;
  const frames = new globalThis.Map();
  class Map {
    constructor(options) { this.options = options; this.sources = new globalThis.Map(); this.layers = new globalThis.Map(); this.events = {}; this.pitch = 55; map = this; calls.push('create'); }
    on(event, layer, callback) { this.events[event] = callback ?? layer; }
    addControl() {}
    addSource(id, source) { assert.ok(!this.sources.has(id)); this.sources.set(id, { ...source, updates: 0, setData(data) { this.data = data; this.updates++; } }); }
    getSource(id) { return this.sources.get(id); }
    removeSource(id) { this.sources.delete(id); }
    addLayer(layer) { assert.ok(!this.layers.has(layer.id)); this.layers.set(layer.id, layer); }
    getLayer(id) { return this.layers.get(id); }
    removeLayer(id) { this.layers.delete(id); }
    setTerrain(options) { assert.ok(this.sources.has(options.source)); }
    jumpTo(options) { this.pitch = options.pitch ?? this.pitch; this.zoom = options.zoom ?? this.zoom; calls.push('jump'); }
    fitBounds(bounds, options) { this.pitch = options.pitch; calls.push({ fit: bounds }); }
    getCenter() { return { toArray() { return [103.864, 1.292]; } }; }
    getZoom() { return this.zoom ?? 15; }
    getBearing() { return 0; }
    resize() { calls.push('resize'); }
    easeTo(options) { this.pitch = options.pitch ?? this.pitch; }
    getPitch() { return this.pitch; }
    stop() { calls.push('pause'); }
    remove() { calls.push('dispose'); }
  }
  const context = { performance: { now() { return now; } }, requestAnimationFrame(callback) { frames.set(++rafID, callback); return rafID; }, cancelAnimationFrame(id) { frames.delete(id); }, document, window: { addEventListener() {}, webkit: { messageHandlers: { map: { postMessage(message) { calls.push(message); } } } } }, mapboxgl: { Map, NavigationControl: class {}, Marker: class { setLngLat() { return this; } addTo() { return this; } remove() {} } } };
  context.window.mapboxgl = context.mapboxgl;
  vm.runInNewContext(script, context);
  return { window: context.window, elements, calls, frame(time) { now = time; const callbacks = [...frames.values()]; frames.clear(); callbacks.forEach(c => c(time)); }, get map() { return map; }, get pendingFrames() { return frames.size; } };
}

test('missing token, reused camera, pending radar, pause and disposal', () => {
  const p = page();
  const data = { publicToken: '', center: [103.864, 1.292], cameraKey: 'singapore', geometry: null, drivers: [] };
  p.window.updateMap(data);
  assert.match(p.elements.get('status').textContent, /未配置/);
  assert.equal(p.calls.length, 0);
  p.window.setRadar(123);
  p.window.updateMap({ ...data, publicToken: 'pk.test' });
  p.map.events['style.load'](); p.map.events.load();
  assert.equal(p.map.options.style, 'mapbox://styles/mapbox/standard');
  assert.equal(p.map.options.config.basemap.lightPreset, 'night');
  assert.equal(p.map.getSource('radar').maxzoom, 7);
  assert.match(p.map.getSource('radar').tiles[0], /pitpulse-radar:\/\/radar\/123/);
  assert.equal(p.map.getSource('track').data.features.length, 0);
  const source = p.map.getSource('radar');
  p.window.updateMap({ ...data, publicToken: 'pk.test', selected: '44', drivers: [{ number: '44', longitude: 103.864, latitude: 1.292, label: 'HAM' }] });
  p.window.setRadar(123);
  assert.equal(p.map.getSource('radar'), source);
  assert.equal(p.map.getSource('cars').data.features[0].properties.selected, true);
  assert.equal(p.calls.filter(c => c === 'create').length, 1);
  assert.equal(p.calls.filter(c => c === 'jump').length, 1);
  p.window.setRadar(null);
  assert.equal(p.map.getSource('radar'), undefined);
  assert.equal(p.map.getSource('coverage'), undefined);
  p.window.pauseMap(); p.window.disposeMap();
  assert.ok(p.calls.includes('pause') && p.calls.includes('dispose'));
});

test('Mapbox failure stays visible across fresh snapshots', () => {
  const p = page(), data = { publicToken: 'pk.test', center: [0, 0], cameraKey: 'x', geometry: null, drivers: [] };
  p.window.updateMap(data); p.map.events['style.load'](); p.map.events.load();
  p.map.events.error({ error: { status: 401 } });
  p.window.updateMap(data);
  assert.match(p.calls.find(c => c.type === 'error').value, /token 无效/);
  assert.ok(p.calls.some(c => c.type === 'error'));
});

test('Mapbox diagnostics expose the error without resource URLs or tokens', () => {
  const p = page();
  p.window.updateMap({ publicToken: 'pk.test', center: [0, 0], cameraKey: 'x', drivers: [] });
  p.map.events.error({ error: { message: 'Blob decoding failed https://api.mapbox.com/tile?access_token=pk.private' } });
  assert.match(p.calls.find(c => c.type === 'error').value, /Blob decoding failed/);
  assert.doesNotMatch(JSON.stringify(p.calls), /access_token|pk\.private/);
});

test('Night map keeps circuit and cars visible with team colours and racing numbers', () => {
  const p = page();
  p.window.updateMap({ publicToken: 'pk.test', center: [0, 0], cameraKey: 'x', drivers: [] });
  p.map.events['style.load'](); p.map.events.load();
  assert.equal(p.map.getLayer('track-line').paint['line-emissive-strength'], 1);
  assert.equal(p.map.getLayer('driver-dots').paint['circle-emissive-strength'], 1);
  assert.equal(p.map.getLayer('driver-labels').paint['text-emissive-strength'], 1);
  assert.deepEqual(Array.from(p.map.getLayer('driver-labels').layout['text-field']), ['get', 'number']);
  assert.deepEqual(Array.from(p.map.getLayer('driver-dots').paint['circle-color']), ['get', 'color']);
  assert.equal(p.map.getLayer('driver-labels').layout['text-allow-overlap'], false);
  assert.equal(p.map.getLayer('driver-dots').layout['circle-sort-key'][2], 1);
  assert.equal(p.map.getLayer('driver-labels').layout['symbol-sort-key'][2], 0);
  assert.equal(p.map.options.config.basemap.showPointOfInterestLabels, false);
  assert.equal(p.map.options.config.basemap.showLandmarkIcons, false);
  assert.equal(p.map.options.fadeDuration, 0, 'Moving racing numbers must not repeatedly fade in');
  p.elements.get('follow').onclick();
  assert.equal(p.map.getZoom(), 16.5, 'Following centres must not cancel the initial zoom');
});


test('Whole circuit is fitted once; 10Hz car updates interpolate and leave geometry untouched', () => {
  const p = page();
  const data = { publicToken: 'pk.test', center: [103.864, 1.292], cameraKey: 'x', pitch: 55,
    geometry: { type: 'Feature', geometry: { type: 'LineString', coordinates: [[103.85, 1.28], [103.87, 1.30]] } },
    drivers: [{ number: '3', color: '#3671C6', longitude: 103.85, latitude: 1.28 }] };
  p.window.updateMap(data); p.map.events['style.load'](); p.map.events.load(); p.frame(100);
  p.window.updateMap({ ...data, selected: '3', drivers: [{ ...data.drivers[0], longitude: 103.86 }] });
  p.frame(150);
  assert.ok(Math.abs(p.map.getSource('cars').data.features[0].geometry.coordinates[0] - 103.855) < 1e-8);
  p.frame(200);
  assert.equal(p.map.getSource('cars').data.features[0].geometry.coordinates[0], 103.86);
  assert.equal(p.map.getSource('track').updates, 0);
  assert.equal(p.calls.filter(c => c.fit).length, 1);
  p.window.pauseMap(); assert.equal(p.pendingFrames, 0);
  const camera = p.calls.find(c => c.type === 'camera').value;
  p.window.disposeMap();
  p.window.updateMap({ ...data, camera }); p.map.events['style.load'](); p.map.events.load();
  assert.equal(p.calls.filter(c => c.fit).length, 1, 'Reopen restores the saved camera');
  assert.equal(p.calls.filter(c => c === 'jump').length, 1);
});

test('Map instance survives hide and resume, resizes, and reports vehicle counts', () => {
  const p = page();
  const data = { publicToken: 'pk.test', center: [103.864, 1.292], cameraKey: 'race-1', geometry: null,
    clientAccepted: 1, positionDiagnostics: { received: 1, decoded: 1, calibrated: 1 },
    drivers: [{ number: '44', longitude: 103.864, latitude: 1.292 }] };
  p.window.updateMap(data); p.map.events['style.load'](); p.map.events.load();
  p.window.pauseMap(); p.window.updateMap(data);
  assert.equal(p.calls.filter(c => c === 'create').length, 1);
  assert.ok(p.calls.includes('resize'));
  const diagnostics = p.calls.find(c => c.type === 'positionDiagnostics');
  assert.equal(diagnostics.value.accepted, 1);
  assert.equal(diagnostics.value.drawn, 1);
  p.window.setRadar(17);
  assert.ok(p.map.getSource('radar'));
  p.window.pauseMap();
  assert.equal(p.map.getSource('radar'), undefined, 'hidden maps stop requesting radar tiles');
  p.window.updateMap(data);
  p.window.setRadar(17);
  assert.ok(p.map.getSource('radar'), 'radar resumes on the retained map');
  p.window.updateMap({ ...data, cameraKey: 'race-2', drivers: [] });
  assert.equal(p.map.getSource('cars').data.features.length, 0, 'a new session clears the old car layer');
  assert.equal(p.calls.filter(c => c === 'create').length, 1);
});
