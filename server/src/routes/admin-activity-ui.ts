export const activityMarkup = `
<section class="section" aria-labelledby="activityTitle">
  <div class="section-head"><div><div class="section-kicker">Visit & Learn</div><h2 id="activityTitle">活跃概览</h2></div><div class="section-note">设备数按整个窗口去重；次数反映使用频率</div></div>
  <form id="activityFilters" class="detail-controls">
    <label>统计时间<select id="activityPreset"><option value="1">今天</option><option value="7">近 7 天</option><option value="30" selected>近 30 天</option><option value="90">近 90 天</option><option value="all">不限时间</option><option value="custom">自定义</option></select></label>
    <label>开始日期（北京时间）<input id="activityStart" type="date"></label>
    <label>结束日期（北京时间）<input id="activityEnd" type="date"></label>
    <label>行为发生时的环境<select id="activityEnvironment"><option value="All">全部环境</option><option value="Production">正式环境</option><option value="Sandbox">沙盒环境</option><option value="Xcode">Xcode</option><option value="LocalTesting">本地测试</option><option value="Unknown">未知</option></select></label>
    <div class="detail-actions"><button type="submit">查看统计</button></div>
  </form>
  <p id="activityCoverage" class="detail-note"></p>
  <div id="activityCards" class="cards" aria-live="polite"></div>
  <div class="grid" style="margin-top:16px">
    <div class="panel span-7"><div class="panel-title"><h3>每天的访问与学习</h3></div><div id="activityDaily" class="table-wrap"></div></div>
    <div class="panel span-5"><div class="panel-title"><h3>功能使用</h3></div><div id="activityBehaviors" class="table-wrap"></div></div>
  </div>
</section>`;

export const activityScript = String.raw`
const activityNames={app_foreground:'进入前台',app_open:'App 打开',recognition_attempt:'识别尝试',recognition_success:'识别成功',listening_enter:'听音找词进入',listening_start:'开始一轮',listening_answer:'完成一道题',listening_complete:'完成一轮',history_view:'查看历史照片',word_play:'主动听词'};
function activityDeviceCells(a){const covered=a?.clientActivityCovered;return '<td>'+escapeHtml(a?.lastActiveAt?(covered?beijingTime(a.lastActiveAt):dateKey(new Date(a.lastActiveAt))+'（仅识别日期）'):'数据未覆盖')+'</td><td>'+fmt(a?.activeDays)+'</td><td>'+(covered?fmt(a.opens):'未覆盖')+'</td><td>'+fmt((a?.recognitionSuccesses||0)+(a?.listeningAnswers||0)+(a?.wordPlays||0))+'</td>'}
function renderActivity(a){
if(!a)return;
syncActivityFilters();
const behaviorMap=new Map(a.behaviors.map(row=>[row.eventName,row]));
const cards=[['访问活跃设备',fmt(a.visitingDevices),'所选期间进入过前台'],['学习活跃设备',fmt(a.learningDevices),'识别成功／答题／主动听词'],['学习参与率',pct(a.participatingVisitors,a.visitingDevices),'访问设备中发生学习的比例'],['近 7 天活跃设备',fmt(a.last7DayDevices),'截至 '+a.windowEndDate],['近 30 天活跃设备',fmt(a.last30DayDevices),'截至 '+a.windowEndDate],['识别成功率',pct(behaviorMap.get('recognition_success')?.count||0,behaviorMap.get('recognition_attempt')?.count||0),'所选期间成功次数／尝试次数']];
$('activityCards').innerHTML=cards.map(([label,value,note])=>'<div class="card"><div class="card-label">'+label+'</div><div class="card-value">'+value+'</div><div class="card-foot">'+escapeHtml(note)+'</div></div>').join('');
$('activityCoverage').textContent='新行为统计自 '+(a.recordingStartedAt?beijingTime(a.recordingStartedAt):'上线')+' 开始，仅覆盖已升级并成功上报的设备；历史识别沿用已有服务端数据。打开次数：冷启动或后台满 30 分钟后返回；自动播音不计主动听词。';
const rows=new Map(a.daily.map(row=>[row.date,row]));
const coverageDay=a.recordingStartedAt?dateKey(new Date(a.recordingStartedAt)):null;
const coverageNote=(a.startDate&&coverageDay&&a.startDate<coverageDay)?'<p class="detail-note">启用前的客户端行为显示“未覆盖”；学习设备可能仅含历史识别，不能作为完整学习活跃数据。</p>':'';
if(a.startDate&&a.endDate){for(let date=a.startDate,limit=0;date<=a.endDate&&limit<3660;date=shiftDate(date,1),limit++)if(!rows.has(date))rows.set(date,{date,visitingDevices:0,learningDevices:0,opens:0})}
const daily=[...rows.values()].sort((x,y)=>y.date.localeCompare(x.date));
const max=daily.reduce((value,row)=>Math.max(value,row.visitingDevices,row.learningDevices),1);
$('activityDaily').innerHTML='<table><thead><tr><th>日期</th><th>访问设备</th><th>学习设备</th><th>打开次数</th></tr></thead><tbody>'+daily.map(row=>'<tr><td>'+escapeHtml(row.date)+'</td><td>'+(coverageDay&&row.date<coverageDay?'未覆盖':fmt(row.visitingDevices))+'<div class="track" aria-hidden="true"><div class="fill" style="background:var(--sky);width:'+(row.visitingDevices/max*100)+'%"></div></div></td><td>'+fmt(row.learningDevices)+'<div class="track" aria-hidden="true"><div class="fill" style="background:var(--mint);width:'+(row.learningDevices/max*100)+'%"></div></div></td><td>'+(coverageDay&&row.date<coverageDay?'未覆盖':fmt(row.opens))+'</td></tr>').join('')+'</tbody></table>'+coverageNote+(daily.length?'':'<p class="detail-note">暂无已上报行为</p>');
const behaviors=Object.keys(activityNames).filter(name=>name!=='app_foreground').map(eventName=>behaviorMap.get(eventName)||{eventName,count:0,devices:0});
$('activityBehaviors').innerHTML='<table><thead><tr><th>行为</th><th>次数</th><th>设备数</th></tr></thead><tbody>'+behaviors.map(row=>'<tr><td>'+activityNames[row.eventName]+'</td><td>'+fmt(row.count)+'</td><td>'+fmt(row.devices)+'</td></tr>').join('')+'</tbody></table>';
}
function syncActivityFilters(){
$('activityPreset').value=dateRange.preset;$('activityStart').value=dateRange.startDate;$('activityEnd').value=dateRange.endDate;
for(const id of ['activityStart','activityEnd'])$(id).disabled=dateRange.preset==='all';
}
$('activityPreset').addEventListener('change',()=>{const preset=$('activityPreset').value;dateRange=preset==='all'?{preset,startDate:'',endDate:''}:preset==='custom'?{...dateRange,preset}:rangeForDays(Number(preset));syncActivityFilters()});
for(const id of ['activityStart','activityEnd'])$(id).addEventListener('change',()=>{$('activityPreset').value='custom'});
$('activityFilters').addEventListener('submit',event=>{event.preventDefault();const preset=$('activityPreset').value;dateRange={preset,startDate:$('activityStart').value,endDate:$('activityEnd').value};if(preset!=='all'&&(!dateRange.startDate||!dateRange.endDate||dateRange.startDate>dateRange.endDate)){$('generated').textContent='请选择有效的统计日期范围';return}pendingDateRange={...dateRange};void load()});
syncActivityFilters();
`;

export const activityDetailMarkup = `
<h3>设备活跃记录</h3>
<p id="deviceActivityCoverage" class="detail-note"></p>
<div id="deviceActivitySummary" class="detail-summary"></div>
<h4>每日汇总</h4><div id="deviceActivityDaily" class="table-wrap"></div>
<h4>行为时间线</h4><p class="detail-note">时间线保留最近 90 天；识别明细在下方独立展示。结果／版本筛选只作用于识别明细。</p>
<div id="deviceActivityStatus" class="detail-status" role="status" aria-live="polite"></div>
<div id="deviceActivityEvents" class="table-wrap"></div>
<div class="detail-pagination"><button type="button" id="deviceActivityRetry" hidden>重试活跃记录</button><button type="button" id="deviceActivityMore" hidden>更多行为</button></div>
`;

export const activityDetailScript = String.raw`
let activityDetailSequence=0,activityDetailRows=[],activityDetailCursor=null,activityDetailBusy=false;
async function loadDeviceActivityPage(append=false){
if(!detailDeviceId||!detailQuery)return;
const serial=++activityDetailSequence,deviceId=detailDeviceId;
if(!append){activityDetailRows=[];activityDetailCursor=null;$('deviceActivityEvents').innerHTML='';$('deviceActivitySummary').innerHTML='';$('deviceActivityDaily').innerHTML='';$('deviceActivityCoverage').textContent=''}
activityDetailBusy=true;$('deviceActivityMore').disabled=true;$('deviceActivityRetry').hidden=true;$('deviceActivityStatus').textContent='正在读取活跃记录…';
const params=new URLSearchParams({startDate:detailQuery.startDate,endDate:detailQuery.endDate,environment:currentStatsEnvironment});if(append&&activityDetailCursor)params.set('cursor',activityDetailCursor);
try{
const res=await fetch('/admin/api/stats/devices/'+encodeURIComponent(deviceId)+'/activity?'+params.toString());if(!res.ok)throw new Error('HTTP '+res.status);
const data=await res.json();if(serial!==activityDetailSequence)return;
activityDetailRows=append?activityDetailRows.concat(data.events):data.events;activityDetailCursor=data.nextCursor;
const s=data.summary;
$('deviceActivityCoverage').textContent=(s.clientActivityCovered?'':'所选期间未覆盖客户端行为。')+'最近已记录活跃 '+(s.clientActivityCovered?beijingTime(s.lastActiveAt):(s.lastActiveAt?dateKey(new Date(s.lastActiveAt))+'（仅识别日期）':'未覆盖'))+' · 新行为记录自 '+beijingTime(data.recordingStartedAt)+' 开始；未升级的客户端行为无法还原。';
$('deviceActivitySummary').innerHTML=[['活跃天数',s.activeDays],['学习天数',s.learningDays],['打开次数',s.clientActivityCovered?s.opens:'未覆盖'],['进入听音找词',s.clientActivityCovered?s.listeningEnters:'未覆盖'],['开始轮数',s.clientActivityCovered?s.listeningStarts:'未覆盖'],['完成轮数',s.clientActivityCovered?s.listeningCompletions:'未覆盖'],['找到／揭晓',fmt(s.listeningFound)+' / '+fmt(s.listeningRevealed)],['主动听词',s.wordPlays],['历史查看',s.historyViews]].map(([label,value])=>'<div class="detail-metric"><span>'+label+'</span><strong>'+escapeHtml(value)+'</strong></div>').join('');
const days=new Map();for(const row of data.daily){const d=days.get(row.date)||{date:row.date,opens:0,recognition:0,answers:0,plays:0,completions:0};if(row.eventName==='app_open')d.opens+=row.count;if(row.eventName==='recognition_success')d.recognition+=row.count;if(row.eventName==='listening_answer')d.answers+=row.count;if(row.eventName==='word_play')d.plays+=row.count;if(row.eventName==='listening_complete')d.completions+=row.count;days.set(row.date,d)}
$('deviceActivityDaily').innerHTML='<table><thead><tr><th>日期</th><th>打开</th><th>识别成功</th><th>答题</th><th>完成轮数</th><th>主动听词</th></tr></thead><tbody>'+[...days.values()].map(d=>'<tr><td>'+escapeHtml(d.date)+'</td><td>'+fmt(d.opens)+'</td><td>'+fmt(d.recognition)+'</td><td>'+fmt(d.answers)+'</td><td>'+fmt(d.completions)+'</td><td>'+fmt(d.plays)+'</td></tr>').join('')+'</tbody></table>';
$('deviceActivityEvents').innerHTML='<table><thead><tr><th>时间（北京时间）</th><th>行为</th><th>结果</th><th>环境</th><th>版本／构建</th></tr></thead><tbody>'+activityDetailRows.map(row=>'<tr><td>'+escapeHtml(beijingTime(row.occurredAt))+'</td><td>'+escapeHtml(activityNames[row.eventName]||row.eventName)+'</td><td>'+escapeHtml({found:'找到',revealed:'揭晓'}[row.outcome]||'—')+'</td><td>'+escapeHtml(environmentNames[row.environment]||row.environment)+'</td><td>'+escapeHtml(row.appVersion||'未知')+' / '+escapeHtml(row.appBuild||'未知')+'</td></tr>').join('')+'</tbody></table>';
$('deviceActivityStatus').textContent=activityDetailRows.length?'已显示 '+fmt(activityDetailRows.length)+' 条行为':'当前范围内暂无已上报行为；旧版缺失不代表没有使用。';
$('deviceActivityMore').hidden=!activityDetailCursor;
}catch(error){if(serial!==activityDetailSequence)return;$('deviceActivityStatus').textContent='活跃记录暂时无法读取：'+error.message;$('deviceActivityRetry').hidden=false}
finally{if(serial===activityDetailSequence){activityDetailBusy=false;$('deviceActivityMore').disabled=false}}
}
$('deviceActivityMore').addEventListener('click',()=>{if(!activityDetailBusy&&activityDetailCursor)void loadDeviceActivityPage(true)});
$('deviceActivityRetry').addEventListener('click',()=>{void loadDeviceActivityPage(Boolean(activityDetailRows.length&&activityDetailCursor))});
`;
