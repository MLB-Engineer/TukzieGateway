/* Same-origin WebSocket relay. Values expire independently after five seconds. */
const RAW_FIELDS = {
  cImu: [['stm-fimu-pitch',1,'pitch'],['stm-fimu-roll',1,'roll']],
  rImu: [['stm-rimu-pitch',1,'pitch'],['stm-rimu-roll',1,'roll']],
  fRadar: [['stm-fradar',2]], bRadar: [['stm-bradar',2]],
  throttle: [['stm-throttle',0]], brake: [['stm-brake',0]],
  lever: [['stm-lever',null]], light: [['stm-light',0]], rain: [['stm-rain',2]],
  bSOC: [['stm-batt-soc',0]], bVoltage: [['stm-batt-voltage',1]],
  bTemp: [['stm-batt-temp',1]], bCurrent: [['stm-batt-current',2]], bFault: [['stm-batt-fault',null]]
};
function num(value) {
  if (value === null || value === undefined || typeof value === 'boolean' || typeof value === 'object' || String(value).trim() === '') return null;
  const n = Number(value); return Number.isFinite(n) ? n : null;
}
function updateRawSensorCards(raw) {
  for (const [key, targets] of Object.entries(RAW_FIELDS)) {
    let value=raw[key];
    if (key === 'cImu' || key === 'rImu') {
      try { value=typeof value==='string'?JSON.parse(value):value; } catch { value=null; }
    }
    for (const [id,decimals,axis] of targets) {
      const element=document.getElementById(id); if(!element)continue;
      const v=axis?value?.[axis]:value;
      element.textContent=decimals===null?(v??'--'):(num(v)===null?'--':num(v).toFixed(decimals));
    }
  }
  const gps=raw.gps && typeof raw.gps==='object'?raw.gps:raw;
  const lat=num(gps.latitude??gps.lat),lon=num(gps.longitude??gps.lon??gps.lng);
  const location=document.getElementById('location-note');
  if(location) {
    const precision=document.body.dataset.role==='guest'?2:6;
    location.textContent=lat!==null&&lon!==null&&Math.abs(lat)<=90&&Math.abs(lon)<=180
      ? `${lat.toFixed(precision)}, ${lon.toFixed(precision)}`:'No live GPS coordinates available.';
  }
}
class SensorManager {
  constructor() {
    this.readings={}; this.timestamps={}; this.ws=null; this.connected=false;
    this.sensorTimeoutMs=5000; this.reconnectTimer=null; this.stopped=false;
    this.lastPacketAt=null;
    this.staleTimer=setInterval(()=>this._checkStaleSensors(),500);
  }
  connect() {
    if(this.ws)return;
    this.stopped=false;
    const protocol=location.protocol==='https:'?'wss:':'ws:';
    const ws=new WebSocket(`${protocol}//${location.host}/ws/telemetry`); this.ws=ws;
    ws.onopen=()=>{this.connected=true;};
    ws.onmessage=event=>{
      try {
        const packet=JSON.parse(event.data);
        if(!packet || typeof packet!=='object' || Array.isArray(packet))return;
        const now=Date.now(),serverNow=packet._server_time ?? now/1000;
        for(const [key,value] of Object.entries(packet)) {
          if(key.startsWith('_'))continue;
          const received=packet._field_received_at?.[key] ?? packet._received_at ?? serverNow;
          this.readings[key]=value;
          this.timestamps[key]=now-Math.max(0,serverNow-received)*1000;
        }
        if(Object.keys(this.readings).length) this.lastPacketAt=now-Math.max(0,serverNow-(packet._received_at??serverNow))*1000;
        const current=this.getAllReadings();
        updateRawSensorCards(current);
        // Keep the existing higher-level widgets for Operator and Guest.
        window.dispatchEvent(new CustomEvent('telemetry-update',{detail:{telemetry:{...current,_received_at:(this.lastPacketAt??0)/1000}}}));
        this._checkStaleSensors();
      } catch(error) { console.warn('Invalid telemetry packet:',error.message); }
    };
    ws.onclose=()=>{
      if(this.ws!==ws)return;
      this.ws=null;this.connected=false;
      if(!this.stopped)this.reconnectTimer=setTimeout(()=>this.connect(),2000);
    };
    ws.onerror=()=>ws.close();
  }
  disconnect() {
    this.stopped=true;clearTimeout(this.reconnectTimer);
    const ws=this.ws;this.ws=null;this.connected=false;ws?.close();
  }
  _checkStaleSensors() {
    updateRawSensorCards(this.getAllReadings());
    const age=this.lastPacketAt===null?null:Date.now()-this.lastPacketAt;
    const status=document.getElementById('feed-status');
    if(status) {
      const fresh=age!==null&&age<=this.sensorTimeoutMs;
      status.classList.toggle('is-live',fresh);
      status.textContent=fresh?'Live telemetry · updated just now':age===null?'Waiting for telemetry':`Telemetry stale · last received ${Math.floor(age/1000)} s ago`;
    }
    // Don't leave the header looking live after a publisher stops.
    if(age===null||age>this.sensorTimeoutMs) {
      for(const id of ['status-temp','status-battery']) {const el=document.getElementById(id);if(el)el.textContent='--';}
    }
  }
  reset() {this.readings={};this.timestamps={};this.lastPacketAt=null;updateRawSensorCards({});}
  getReading(key) {return this.isSensorLive(key)?this.readings[key]??null:null;}
  getAllReadings() {return Object.fromEntries(Object.entries(this.readings).filter(([key])=>this.isSensorLive(key)));}
  isConnected() {return this.connected;}
  isSensorLive(key) {return this.timestamps[key]!==undefined&&Date.now()-this.timestamps[key]<=this.sensorTimeoutMs;}
}
window.sensorManager=new SensorManager();
