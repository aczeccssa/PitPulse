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
 location: { hash: '#/head-to-head?season=2021' },
 state: { driversStandings: [{ season: 2026 }] },
 artSeasonValue: 2026,
 driverPages: {season: 2026},
 URLSearchParams,
});
vm.runInContext(functionSource('requestedSeason'), context);
vm.runInContext(functionSource('artSeason'), context);
assert.equal(vm.runInContext('artSeason()', context), 2021, 'background render must not overwrite requested media season');
context.location.hash = '#/driver-standings?season=2024';
assert.equal(vm.runInContext('artSeason()', context), 2024);
vm.runInContext(functionSource('seasonDriver'), context);
context.driver = { driverId: 'max_verstappen', season: 2021, driverNumber: '3', constructor: 'Red Bull' };
context.entries = [{ sessions: { race: { rows: [{ driverId: 'max_verstappen', driverNumber: '33', team: 'Red Bull', constructorId: 'red_bull' }] } } }];
context.driverRow = (e, kind, id) => e.sessions[kind]?.rows?.find(r => r.driverId === id);
assert.equal(vm.runInContext('seasonDriver(driver, entries, 2021).driverNumber', context), '33');
assert.match(source, /loadCalendar\(season\), loadStandings\(season\)/, 'boot must use requested season');
console.log('PASS: requested season survives bootstrap; racing number comes from that season results');
