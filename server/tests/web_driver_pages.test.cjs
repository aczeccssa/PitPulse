// Focused browser-independent checks for season comparisons. Run with node --test.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const vm = require('node:vm');
const source = readFileSync(resolve(__dirname, '../resources/web/app.js'), 'utf8');
const context = vm.createContext({
    document: {addEventListener() {}},
    teamAssetId(value) { return value === 'alpha' || value === 'beta' ? value : null; },
    lapSeconds(value) {
        if (!/^\d+:\d{2}\.\d+$/.test(value || '')) return Infinity;
        const [minutes, seconds] = value.split(':').map(Number);
        return minutes * 60 + seconds;
    },
});
vm.runInContext(source.slice(source.indexOf('    /* ---------- Drivers, driver statistics'), source.indexOf('    function meetingFlag')) + '\nglobalThis.subject = {comparisonPoints, qualifyingGaps, driverStats, selectedComparisonPairs, driverPages, positionQuantile, consistencyDistribution, engineeringFilterRows, engineeringCounts, powerUnitRows, powerUnitClass, elementKey, engineeringPenaltyRows, crashModel, homeSchedule, homeRecords};', context);
const { comparisonPoints, qualifyingGaps, driverStats, selectedComparisonPairs, driverPages, positionQuantile, consistencyDistribution, engineeringFilterRows, engineeringCounts, powerUnitRows, powerUnitClass, elementKey, engineeringPenaltyRows, crashModel, homeSchedule, homeRecords } = context.subject;
const row = (id, team, position, extra = {}) => ({driverId:id, driverName:id, team, constructorId:team, position, classification:'classified', ...extra});
const entry = (round, sessions) => ({meeting:{round}, sessions:Object.fromEntries(Object.entries(sessions).map(([type, rows]) => [type, {rows}]))});
const drivers = ['a', 'b'].map((id, index) => ({driverId:id, driverName:id, constructor:'alpha', position:index+1, points:25-index*7}));

test('chart entrance animates visible data marks and leaves hit targets and grid lines alone', () => {
    const animateChart = vm.runInContext(source.slice(source.indexOf('    function animateChart'), source.indexOf('    function wireContentMotion')) + '\nanimateChart', context);
    function mark(tag, attributes = {}) {
        return {
            closest: () => null,
            matches: selector => selector.split(', ').some(value => value === tag || value === attributes.class),
            getAttribute: key => attributes[key] ?? null,
            getTotalLength: () => 80,
            animate(frames, options) { this.frames = frames; this.options = options; },
        };
    }
    const line = mark('path', {stroke: 'red'});
    const bar = mark('rect', {width: 10, height: 40});
    const dot = mark('circle');
    const ring = mark('circle', {'stroke-dasharray': '20 60'});
    const grid = mark('line', {class: '.progress-grid', stroke: 'grey'});
    const hit = mark('rect', {fill: 'transparent'});
    animateChart({querySelectorAll: () => [line, bar, dot, ring, grid, hit]});
    assert.equal(line.frames[0].strokeDashoffset, 80);
    assert.equal(bar.frames[0].scale, '1 .03');
    assert.equal(dot.frames[0].scale, '.35');
    assert.equal(ring.frames[0].strokeDasharray, '0 60');
    assert.equal(ring.options.fill, 'backwards');
    assert.equal(grid.frames, undefined);
    assert.equal(hit.frames, undefined);
});

test('Home schedule excludes cancellations and finished sessions while counting actual race results', () => {
    const now=Date.parse('2026-11-17T12:00:00Z');
    const session=(startTime,status='scheduled')=>({sessionType:'fp1',startTime,endTime:'2026-11-17T14:00:00Z',status});
    const calendar=[
        {id:'next',round:3,sessions:[session('2026-11-18T12:00:00Z')]},
        {id:'cancelled',round:2,status:'cancelled',sessions:[session('2026-11-17T12:30:00Z')]},
        {id:'previous',round:1,sessions:[session('2026-11-17T11:00:00Z','finished')]},
        {id:'testing',round:null,sessions:[session('2026-11-17T12:15:00Z')]},
    ];
    const schedule=homeSchedule(calendar,[{meeting:{id:'previous'},sessions:{race:{rows:[row('a','alpha',1)]}}}],now);
    assert.equal(schedule.current,undefined);
    assert.equal(schedule.next.meeting.id,'next');
    assert.equal(schedule.completed,1);
    assert.equal(schedule.total,2);
    assert.equal(calendar[0].id,'next');
    const finished=homeSchedule(calendar,[],Date.parse('2027-01-01T00:00:00Z'));
    assert.equal(finished.next,undefined);
    assert.equal(finished.display.id,'next');
    assert.equal(homeSchedule([],[],now).display,undefined);
});

test('Home records derive podiums and position gains from classified results and keep the selected season', () => {
    driverPages.season=2025;
    const race=entry(1,{race:[row('a','alpha',1,{driverNumber:'7',gridPosition:2}),row('b','alpha',2,{gridPosition:8}),row('c','beta',20,{gridPosition:1,classification:'DNF'})]});
    race.meeting={...race.meeting,id:'2025:1',location:'Melbourne',sessions:[{sessionType:'race',startTime:'2025-03-16T04:00:00Z'}]};
    const records=homeRecords({entries:[race],summary:{drivers:[{driverNumber:7,rookie:true}]}});
    assert.deepEqual(Array.from(records,r=>r.category),['Race','Team','Driver','Rookie']);
    assert.match(records.find(r=>r.category==='Driver').title,/b gains 6 places/);
    assert.equal(records[0].href,'/results/2025%3A1/race?season=2025');
    assert.equal(homeRecords({entries:[],summary:{}}).length,0);
});

test('teammate comparisons exclude sessions before a transfer and both retirements', () => {
    const data = {entries:[
        entry(1, {race:[row('a','alpha',1),row('b','beta',2)]}),
        entry(2, {race:[row('a','alpha',2),row('b','alpha',1)]}),
        entry(3, {race:[row('a','alpha',null,{classification:'DNF'}),row('b','alpha',null,{classification:'DNF'})]}),
        entry(4, {race:[row('a','alpha',1),row('b','alpha',null,{classification:'DNF'})]}),
    ]};
    const paired = comparisonPoints(data,'a','b',['race'],'alpha');
    assert.equal(paired.matches.length,2);
    assert.equal(paired.left,1);
    assert.equal(paired.right,1);
    assert.equal(comparisonPoints(data,'a','b',['race']).left,2);
});

test('qualifying gaps compare matching phases and preserve exact signs', () => {
    const data = {entries:[entry(1, {qualifying:[
        row('a','alpha',1,{q1:'1:21.000',q2:'1:20.000',q3:'1:19.000'}),
        row('b','alpha',12,{q1:'1:21.200',q2:'1:20.400'}),
    ]})]};
    const dots = qualifyingGaps(data,{first:drivers[0],second:drivers[1],team:'alpha'},['qualifying']);
    assert.equal(dots.length,2);
    assert.equal(dots[0].phase,'q1');
    assert.ok(Math.abs(dots[0].gap + 0.2) < 1e-8);
    assert.ok(Math.abs(dots[1].gap + 0.4) < 1e-8);
});

test('official numbered retirement positions retain finish distribution and ordering', () => {
    const data = {drivers,entries:[entry(1,{race:[row('a','alpha',20,{classification:'DNF'}),row('b','alpha',21,{classification:'DNF'})]})]};
    assert.equal(comparisonPoints(data,'a','b',['race']).left,1);
    const stats=driverStats(data,drivers[0]);
    assert.equal(stats.positions[0],20);
    assert.equal(stats.dnfs,1);
    assert.equal(stats.average,20);
});

test('incompatible qualifying phases do not fall back to unrelated best laps', () => {
    const data = {entries:[entry(1, {qualifying:[
        row('a','alpha',1,{q3:'1:19.000',bestLap:'1:19.000'}),
        row('b','alpha',18,{q1:'1:22.000',bestLap:'1:22.000'}),
    ]})]};
    assert.equal(qualifyingGaps(data,{first:drivers[0],second:drivers[1],team:'alpha'},['qualifying']).length,0);
});

test('season statistics separate race, sprint, unclassified and missing results', () => {
    const data = {drivers,entries:[
        entry(1,{race:[row('a','alpha',1,{points:25})],sprint:[row('a','alpha',1,{points:8})],qualifying:[row('a','alpha',1)]}),
        entry(2,{race:[row('a','alpha',null,{classification:'DNF',points:0})]}),
        entry(3,{}),
    ]};
    const stats = driverStats(data,drivers[0]);
    assert.equal(stats.races.length,2);
    assert.equal(stats.wins,1);
    assert.equal(stats.podiums,1);
    assert.equal(stats.poles,1);
    assert.equal(stats.inPoints,1);
    assert.equal(stats.dnfs,1);
    assert.equal(stats.average,1);
});

test('either driver selector filters pairings, and explicit rivals allow different teams', () => {
    const other = {driverId:'c',driverName:'c',constructor:'beta',position:3};
    const data = {drivers:[...drivers,other],entries:[entry(1,{race:[row('a','alpha',1),row('b','alpha',2),row('c','beta',3)]})]};
    Object.assign(driverPages,{first:'',second:'c',team:''});
    assert.equal(selectedComparisonPairs(data).length,0);
    Object.assign(driverPages,{first:'a',second:'c'});
    assert.equal(selectedComparisonPairs(data)[0].crossTeam,true);
});

test('consistency quartiles interpolate samples and retain a single-result range', () => {
    assert.equal(positionQuantile([], .5), null);
    assert.equal(positionQuantile([1], .25), 1);
    assert.equal(positionQuantile([1, 2, 4, 8], .25), 1.75);
    assert.equal(positionQuantile([1, 2, 4, 8], .5), 3);
    assert.equal(positionQuantile([1, 2, 4, 8], .75), 5);
});

test('consistency excludes retirements only when requested and never invents missing positions', () => {
    const data = {drivers, entries:[
        entry(1,{race:[row('a','alpha',1),row('b','alpha',2)], sprint:[row('a','alpha',8)]}),
        entry(2,{race:[row('a','alpha',20,{classification:'DNF'}),row('b','alpha',null,{classification:'DNF'})]}),
        entry(3,{race:[row('a','alpha',0,{classification:'DNS'}),row('b','alpha',3)]}),
    ]};
    const included=consistencyDistribution(data,'race',false);
    assert.equal(included[0].driver.driverId,'b');
    assert.equal(included.find(g=>g.driver.driverId==='a').median,10.5);
    assert.equal(included.find(g=>g.driver.driverId==='b').values.length,2);
    const excluded=consistencyDistribution(data,'race',true);
    assert.equal(excluded[0].driver.driverId,'a');
    assert.equal(excluded[0].values.length,1);
    assert.equal(excluded[0].max,1);
    assert.equal(consistencyDistribution(data,'sprint',false)[0].min,8);
    assert.equal(consistencyDistribution(data,'qualifying',false).length,0);
});

test('technical report filters intersect and cleared selections yield no updates', () => {
    const rows = [
        {team:'A',type:'Performance',reason:'Load',component:'Wing'},
        {team:'A',type:'Reliability',reason:'Load',component:'Wing'},
        {team:'B',type:'Performance',reason:'Cooling',component:'Floor'},
    ];
    const preference = {teams:null,types:null,reasons:null};
    assert.equal(engineeringCounts(engineeringFilterRows(rows,preference),'component')[0].count,2);
    preference.teams=new Set(['A']);preference.types=new Set(['Performance']);
    assert.equal(engineeringFilterRows(rows,preference).length,1);
    preference.reasons=new Set(['Cooling']);
    assert.equal(engineeringFilterRows(rows,preference).length,0);
    preference.teams=new Set();preference.reasons=null;
    assert.equal(engineeringFilterRows(rows,preference).length,0);
});

test('PU allocation keeps absent counts separate and applies both driver and constructor filters', () => {
    assert.equal(powerUnitClass(null,4),'pu-missing');
    assert.equal(powerUnitClass(3,4),'pu-within');
    assert.equal(powerUnitClass(4,4),'pu-limit');
    assert.equal(powerUnitClass(5,4),'pu-over');
    assert.equal(powerUnitClass(4,0),'pu-neutral');
    assert.equal(elementKey('mguk'),'mgu-k');
    const data={usage:[{team:'A',driverCode:'ONE'},{team:'B',driverCode:'TWO'}]};
    assert.equal(powerUnitRows(data,{teams:new Set(['A']),drivers:new Set(['TWO'])}).length,0);
    assert.equal(powerUnitRows(data,{teams:null,drivers:new Set(['TWO'])})[0].driverCode,'TWO');
});

test('PU penalties combine same-driver decisions while preserving components and unique sources', () => {
    const rows=engineeringPenaltyRows([
        {round:20,driverCode:'HAM',driverName:'Hamilton',gridPositions:65,elements:['ice','tc'],penaltyItems:[{elementCode:'ice'}],sourceDocuments:[{url:'https://www.fia.com/a'}]},
        {round:20,driverCode:'HAM',driverName:'Hamilton',gridPositions:10,elements:['ice'],penaltyItems:[{elementCode:'tc'}],sourceDocuments:[{url:'https://www.fia.com/a'},{url:'https://www.fia.com/b'}]},
        {round:20,driverCode:'LEC',driverName:'Leclerc',gridPositions:5,elements:['ice'],penaltyItems:[{elementCode:'ice'}]},
    ]);
    assert.equal(rows.length,2);
    assert.equal(rows[0].gridPositions,75);
    assert.equal(rows[0].penaltyItems.length,2);
    assert.equal(Array.from(rows[0].elements).join(','),'ice,tc');
    assert.equal(Array.from(rows[0].sourceDocuments,source=>source.url).join(','),'https://www.fia.com/a,https://www.fia.com/b');
});


test('crash costs use component quantities, include zero costs and reconcile all views', () => {
    const source=[
        {driverId:1,driverName:'A',team:'alpha',round:0,country:'Spain',components:[{componentId:1,name:'Wing',price:150000,quantity:2}]},
        {driverId:1,driverName:'A',team:'alpha',round:1,country:'Australia',components:[{componentId:2,name:'Tyre',price:3000,quantity:2}]},
        {driverId:2,driverName:'B',team:'alpha',round:1,country:'Australia',components:[{componentId:1,name:'Wing',price:150000,quantity:1}]},
        {driverId:3,driverName:'C',team:'beta',round:1,country:'Australia',components:[]},
    ];
    const model=crashModel(source,{teams:null,drivers:null});
    assert.equal(model.total,456000);
    assert.equal(model.drivers.length,3);
    assert.equal(model.drivers[2].total,0);
    assert.equal(model.drivers[0].rounds.get(0),300000);
    assert.equal(model.components.find(c=>c.name==='Wing').quantity,3);
    assert.equal(model.components.reduce((sum,c)=>sum+c.total,0),model.total);
    assert.equal(model.events.reduce((sum,e)=>sum+e.total,0),model.total);
    assert.equal(model.teams[0].total,model.total);
    const filtered=crashModel(source,{teams:new Set(['alpha']),drivers:new Set(['B'])});
    assert.equal(filtered.total,150000);
    assert.equal(filtered.drivers.length,1);
    assert.equal(filtered.meetings.length,2);
    assert.equal(crashModel(source,{teams:new Set(),drivers:null}).total,0);
});
