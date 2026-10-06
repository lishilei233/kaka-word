import { activityDetailMarkup } from './admin-activity-ui.js';
export const deviceDetailsStyles = `
.device-table { min-width:720px; }
.device-table .filtered-empty { display:table-cell; text-align:center!important; white-space:normal!important; padding:36px 12px; }
.device-details { position:fixed; inset:0 0 0 auto; margin:0; width:min(1120px,96vw); max-width:100vw; height:100dvh; max-height:100dvh; border:0; border-left:1px solid var(--line); padding:0; overflow-anchor:none; color:var(--ink); background:var(--paper); box-shadow:-18px 0 70px rgba(37,42,43,.22); }
.device-details::backdrop { background:rgba(37,42,43,.42); }
.detail-heading { position:sticky; top:0; z-index:2; display:flex; justify-content:space-between; align-items:center; gap:16px; padding:24px 28px; background:var(--light); border-bottom:1px solid var(--line); }
.detail-heading h2 { margin:6px 0 0; }
.detail-body { padding:24px 28px 40px; }
.detail-profile { color:var(--muted); font-size:13px; line-height:1.8; margin-bottom:16px; }
.detail-controls { display:grid; grid-template-columns:repeat(3,minmax(0,1fr)); gap:12px; padding:18px; border:1px solid var(--line); border-radius:18px; background:var(--light); }
.detail-controls label { font-size:12px; color:var(--muted); font-weight:700; }
.detail-controls input,.detail-controls select { display:block; width:100%; margin-top:6px; border:1px solid var(--line); border-radius:10px; padding:10px; background:var(--paper); }
.detail-actions { display:flex; gap:8px; align-items:end; }
.detail-summary { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; margin:20px 0; }
.detail-metric { padding:16px; background:var(--light); border:1px solid var(--line); border-radius:14px; }
.detail-metric span { display:block; font-size:12px; color:var(--muted); }
.detail-metric strong { display:block; margin-top:8px; font:800 26px Georgia,serif; }
.detail-note { font-size:12px; color:var(--muted); line-height:1.7; }
.detail-status { min-height:28px; margin-top:14px; font-size:13px; color:var(--muted); }
.detail-attempts { min-width:1380px; background:var(--light); }
.detail-attempts th,.detail-attempts td { text-align:left!important; vertical-align:top; }
.detail-attempts small { display:block; color:var(--muted); line-height:1.7; }
.result-badge { display:inline-block; padding:4px 9px; border-radius:8px; background:var(--deep); font-weight:800; }
.result-success { background:rgba(101,185,155,.25); }.result-failure { background:rgba(239,113,95,.2); }.result-processing { background:rgba(132,185,215,.25); }
.detail-pagination { display:flex; justify-content:space-between; align-items:center; margin-top:16px; }
button:focus-visible,input:focus-visible,select:focus-visible { outline:3px solid var(--sky); outline-offset:3px; }
button:disabled { opacity:.5; cursor:default; }
@media(max-width:600px){.device-details{width:100vw}.detail-heading{padding:18px}.detail-body{padding:18px}.detail-controls{grid-template-columns:1fr 1fr}.detail-summary{grid-template-columns:1fr 1fr}.detail-heading h2{font-size:23px}}
`;

export const deviceDetailsMarkup = `
<dialog id="deviceDetails" class="device-details" aria-labelledby="detailTitle">
  <div class="detail-heading"><div><div class="section-kicker">Recognition journal</div><h2 id="detailTitle">设备识别详情</h2></div><button type="button" id="detailClose" aria-label="关闭设备详情">关闭</button></div>
  <div class="detail-body">
    <div id="detailProfile" class="detail-profile"></div>
    <form id="detailFilters" class="detail-controls">
      <label>统计时间范围<select id="detailPreset"><option value="1">今天</option><option value="7">近 7 天</option><option value="30">近 30 天</option><option value="90" selected>近 90 天</option><option value="custom">自定义</option></select></label>
      <label>开始日期（北京时间）<input id="detailStart" type="date" required></label>
      <label>结束日期（北京时间）<input id="detailEnd" type="date" required></label>
      <label>识别结果<select id="detailOutcome"><option value="">全部结果</option><option value="processing">处理中</option><option value="success">成功</option><option value="empty">空结果</option><option value="failure">失败</option><option value="cancelled">取消</option><option value="quota_exhausted">额度耗尽</option><option value="rate_limited">服务限流</option><option value="unfinished">未正常结束</option></select></label>
      <label>App 版本／构建号<input id="detailVersion" type="search" maxlength="64" placeholder="例如 1.2.0 或 35"></label>
      <div class="detail-actions"><button type="submit">应用筛选</button><button type="button" id="detailRefresh" class="clear-filters">刷新</button></div>
    </form>
    ${activityDetailMarkup}
    <h3>识别记录与额度</h3>
    <div id="detailSummary" class="detail-summary"></div>
    <p id="detailHistory" class="detail-note">明细自上线后开始记录，保留最近 90 天；更早的数据仅有每日汇总，无法还原逐次结果。</p>
    <p class="detail-note">时段汇总按识别日期计算，不受结果与版本筛选影响。额度为请求时快照，“是否扣次”按实际额度操作状态判断。</p>
    <div id="detailStatus" class="detail-status" role="status" aria-live="polite"></div>
    <button type="button" id="detailRetry" hidden>重试读取详情</button>
    <div class="table-wrap" id="detailAttempts"></div>
    <div class="detail-pagination"><span class="detail-note" id="detailCount"></span><button type="button" id="detailMore" hidden>加载更多</button></div>
  </div>
</dialog>
`;

export const deviceDetailsScript = String.raw`
const outcomeNames={processing:'处理中',success:'成功',empty:'空结果',failure:'失败',cancelled:'取消',quota_exhausted:'额度耗尽',rate_limited:'服务限流',unfinished:'未正常结束'};
const reasonNames={NO_OBJECTS:'未识别出有效物体',ANALYZE_FAILED:'识别处理失败',CLIENT_DISCONNECTED:'请求连接中断或用户取消',QUOTA_EXHAUSTED:'可用额度不足',DAILY_LIMIT_REACHED:'服务每日限额已达上限',USAGE_LIMIT_UNAVAILABLE:'服务限额暂时不可读取',ATTEMPT_TIMEOUT:'超过 10 分钟仍无明确结束记录'};
const stageNames={daily_limit:'服务限额',vision_provider:'图像识别',serialize_response:'结果与额度处理',quota_reservation:'额度检查'};
const environmentNames={Production:'正式环境',Sandbox:'沙盒环境',Xcode:'Xcode',LocalTesting:'本地测试',Unknown:'未知'};
const membershipNames={free:'免费会员',monthly:'月会员',annual:'年会员'};
let detailDeviceId=null,detailRows=[],detailNextCursor=null,detailSequence=0,detailQuery=null,detailBusy=false;
const beijingTime=value=>value?new Date(value).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',hour12:false}):'—';
function renderAttemptTable(){
const quota=q=>q?('已用 '+fmt(q.used)+' / 剩余 '+(q.unlimited?'不限':fmt(q.remaining))+'<small>预占 '+fmt(q.reserved)+' · 上限 '+(q.unlimited?'不限':fmt(q.limit))+(q.periodStart?'<br>周期 '+escapeHtml(beijingTime(q.periodStart))+' 至 '+escapeHtml(beijingTime(q.resetAt)):'')+'</small>'):'—';
const rows=detailRows.map(x=>'<tr><td>'+escapeHtml(beijingTime(x.startedAt))+'<small>结束 '+escapeHtml(beijingTime(x.finishedAt))+'</small></td><td>'+(x.durationMs===null?'—':(x.durationMs/1000).toFixed(1)+' 秒')+'</td><td><span class="result-badge result-'+x.outcome+'">'+escapeHtml(outcomeNames[x.outcome]||x.outcome)+'</span></td><td>'+escapeHtml(reasonNames[x.reasonCode]||x.reasonCode||'—')+'<small>'+escapeHtml(stageNames[x.stage]||x.stage||'')+'</small></td><td>'+escapeHtml(environmentNames[x.environment]||x.environment)+'</td><td>'+(x.quotaBefore.tier==='free'?'免费额度':'会员周期额度')+'</td><td>'+quota(x.quotaBefore)+'</td><td>'+quota(x.quotaAfter)+'</td><td>'+({committed:'是 · 已扣除',released:'否 · 已释放',reserved:'待定 · 预占中',not_reserved:'否 · 未预占'}[x.quotaState]||'未知')+'</td><td>'+escapeHtml(x.appVersion||'未知')+'<small>构建 '+escapeHtml(x.appBuild||'未知')+'</small></td><td>'+escapeHtml(x.requestId)+'</td></tr>').join('');
$('detailAttempts').innerHTML='<table class="detail-attempts"><thead><tr>'+['识别时间（北京时间）','耗时','结果','原因','请求环境','额度类型','识别前额度','结束时额度','是否扣次','App 版本','请求编号'].map(x=>'<th scope="col">'+x+'</th>').join('')+'</tr></thead><tbody>'+(rows||'<tr><td colspan="11">'+(detailBusy?'正在读取识别记录…':'当前筛选下没有逐次识别记录。历史汇总不能还原为明细。')+'</td></tr>')+'</tbody></table>';
$('detailCount').textContent='已显示 '+fmt(detailRows.length)+' 条记录';
$('detailMore').hidden=!detailNextCursor;
}
function renderDeviceDetails(data){
const d=data.device,s=data.summary;
$('detailTitle').textContent='设备 '+d.deviceId+' · 活跃与识别详情';
$('detailProfile').textContent='注册 '+d.registrationDate+'（北京时间） · '+(environmentNames[d.environment]||d.environment)+' · '+(membershipNames[d.membershipType]||'会员')+' · 当前免费额度 已用 '+d.freeUsed+' / 剩余 '+Math.max(0,3-d.freeUsed);
$('detailSummary').innerHTML=[['识别尝试',fmt(s.recognitionAttempts)],['成功识别',fmt(s.recognitionSuccesses)],['识别成功率',pct(s.recognitionSuccesses,s.recognitionAttempts)],['用户改选率',pct(s.reselectionCount,s.confirmationCount)]].map(([label,value])=>'<div class="detail-metric"><span>'+label+'</span><strong>'+value+'</strong></div>').join('');
$('detailHistory').textContent='明细自 '+beijingTime(data.recordingStartedAt)+' 上线后开始记录，保留最近 90 天；更早的数据仅有每日汇总，无法还原逐次结果。';
}
async function loadDeviceDetailsPage(append=false){
if(!detailDeviceId||!detailQuery)return;
const serial=++detailSequence;
if(!append){detailRows=[];detailNextCursor=null;$('detailSummary').innerHTML=''}
detailBusy=true;$('detailMore').disabled=true;$('detailRetry').hidden=true;$('detailStatus').textContent='正在读取详情…';$('detailAttempts').setAttribute('aria-busy','true');renderAttemptTable();
const params=new URLSearchParams({...detailQuery,environment:currentStatsEnvironment});if(append&&detailNextCursor)params.set('cursor',detailNextCursor);
try{
const res=await fetch('/admin/api/stats/devices/'+encodeURIComponent(detailDeviceId)+'?'+params.toString());
if(!res.ok)throw new Error(res.status===404?'设备记录不存在':'HTTP '+res.status);
const data=await res.json();if(serial!==detailSequence)return;
detailRows=append?detailRows.concat(data.attempts):data.attempts;detailNextCursor=data.nextCursor;renderDeviceDetails(data);$('detailStatus').textContent='识别记录范围：'+data.startDate+' 至 '+data.endDate;
}catch(e){if(serial!==detailSequence)return;$('detailStatus').textContent='详情暂时无法读取：'+e.message;$('detailRetry').hidden=false}
finally{if(serial===detailSequence){detailBusy=false;$('detailMore').disabled=false;$('detailAttempts').setAttribute('aria-busy','false');renderAttemptTable()}}
}
function openDeviceDetails(installationId){
detailDeviceId=installationId;const range=rangeForDays(90);$('detailPreset').value='90';$('detailStart').value=range.startDate;$('detailEnd').value=range.endDate;$('detailOutcome').value='';$('detailVersion').value='';
for(const id of ['detailStart','detailEnd']){$(id).min=range.startDate;$(id).max=range.endDate}
detailQuery={startDate:range.startDate,endDate:range.endDate};$('detailTitle').textContent='设备识别详情';$('detailProfile').textContent='正在读取当前设备信息…';$('deviceDetails').showModal();$('deviceDetails').scrollTop=0;void loadDeviceActivityPage();return loadDeviceDetailsPage();
}
$('detailClose').addEventListener('click',()=>$('deviceDetails').close());
$('deviceDetails').addEventListener('close',()=>{activityDetailSequence++;detailSequence++;detailDeviceId=null;detailBusy=false});
$('deviceDetails').addEventListener('click',event=>{if(event.target===$('deviceDetails')){const bounds=$('deviceDetails').getBoundingClientRect();if(event.clientX<bounds.left||event.clientX>bounds.right||event.clientY<bounds.top||event.clientY>bounds.bottom)$('deviceDetails').close()}});
$('detailPreset').addEventListener('change',()=>{if($('detailPreset').value!=='custom'){const r=rangeForDays(Number($('detailPreset').value));$('detailStart').value=r.startDate;$('detailEnd').value=r.endDate}});
for(const id of ['detailStart','detailEnd'])$(id).addEventListener('change',()=>{$('detailPreset').value='custom'});
$('detailFilters').addEventListener('submit',event=>{event.preventDefault();const start=$('detailStart').value,end=$('detailEnd').value,r=rangeForDays(90);if(!start||!end||start>end||start<r.startDate||end>r.endDate){$('detailStatus').textContent='请选择最近 90 天内有效的识别日期范围';return}detailQuery={startDate:start,endDate:end,outcome:$('detailOutcome').value,appVersion:$('detailVersion').value.trim()};void loadDeviceDetailsPage();void loadDeviceActivityPage()});
$('detailRefresh').addEventListener('click',()=>{void loadDeviceDetailsPage();void loadDeviceActivityPage()});
$('detailRetry').addEventListener('click',()=>{void loadDeviceDetailsPage(Boolean(detailRows.length&&detailNextCursor))});
$('detailMore').addEventListener('click',()=>{if(!detailBusy&&detailNextCursor)void loadDeviceDetailsPage(true)});
`;
