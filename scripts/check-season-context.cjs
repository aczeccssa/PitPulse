// Run with node: scripts/check-season-context.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('server/resources/web/app.js', 'utf8');
function functionSource(name) {
 const start = source.indexOf(`    function ${name}(`);
 assert(start >= 0, `${name} must exist`);
 const end = source.indexOf('\n    }', start);
 return source.slice(start, end + 6);
}
const context = vm.createContext({
 location: { search: '?season=2021' },
 state: { driversStandings: [{ season: 2026 }] },
 artSeasonValue: 2026,
 driverPages: {season: 2026},
 URLSearchParams,
});
vm.runInContext(functionSource('requestedSeason'), context);
vm.runInContext(functionSource('artSeason'), context);
assert.equal(vm.runInContext('artSeason()', context), 2021, 'background render must not overwrite requested media season');
context.location.search = '?season=2024';
assert.equal(vm.runInContext('artSeason()', context), 2024);
vm.runInContext(functionSource('seasonDriver'), context);
context.driver = { driverId: 'max_verstappen', season: 2021, driverNumber: '3', constructor: 'Red Bull' };
context.entries = [{ sessions: { race: { rows: [{ driverId: 'max_verstappen', driverNumber: '33', team: 'Red Bull', constructorId: 'red_bull' }] } } }];
context.driverRow = (e, kind, id) => e.sessions[kind]?.rows?.find(r => r.driverId === id);
assert.equal(vm.runInContext('seasonDriver(driver, entries, 2021).driverNumber', context), '33');
// Standings now load on demand when their route renders.
context.state.view = 'standings';
context.el = () => ({});
context.loadStandings = season => { context.loadedSeason = season; throw new Error('season captured'); };
vm.runInContext(functionSource('renderStandingsPage'), context);
assert.throws(() => vm.runInContext('renderStandingsPage()', context), /season captured/);
assert.equal(context.loadedSeason, 2024, 'standings must load the requested season');
console.log('PASS: requested season survives bootstrap; racing number comes from that season results');

// Historical driver avatars use artwork from the selected season.
context.ASSETS = {
 '2024/driver-photo/max_verstappen.png': '2024-portrait',
 '2025/driver-photo/max_verstappen.png': '2025-portrait',
 '2026/driver-photo/max_verstappen.png': '2026-portrait',
 '2026/helmet/max_verstappen.png': '2026-helmet',
};
context.DRIVER_ALIASES = { verstappen: 'max_verstappen' };
context.artImage = (className, src) => ({className, src});
for (const name of ['hasAsset', 'mediaSrc', 'assetSrc', 'driverAssetId', 'helmetImage', 'driverPhotoArt', 'driverAvatarImage']) {
 vm.runInContext(functionSource(name), context);
}
for (const [year, digest] of [[2024, '2024-portrait'], [2025, '2025-portrait'], [2026, '2026-helmet']]) {
 assert.equal(vm.runInContext(`driverAvatarImage(${year}, 'verstappen').src`, context), `/media/blob/${digest}`);
}
assert.equal(vm.runInContext("driverAvatarImage(2023, 'verstappen')", context), null);
console.log('PASS: driver avatars use only the selected season assets and prefer its helmet');
