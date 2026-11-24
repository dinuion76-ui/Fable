// Renders build/parts.json with three.js in headless Chromium (a rough stand-in for Studio).
// usage: node render.js <three.min.js> <outDir> [--parts file.json] [--views views.json] [viewName ...]
//   --views replaces the built-in views; each view: { pos, look, fov | ortho, w, h, fog, fogd, sun: [dx,dy,dz] }
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const threePath = process.argv[2];
const outDir = process.argv[3];
const rest = process.argv.slice(4);
let partsFile = path.join(__dirname, '../../build/parts.json');
let viewsFile = null;
const only = [];
for (let i = 0; i < rest.length; i++) {
  if (rest[i] === '--parts') partsFile = rest[++i];
  else if (rest[i] === '--views') viewsFile = rest[++i];
  else only.push(rest[i]);
}
const parts = fs.readFileSync(partsFile, 'utf8');

const VIEWS = {
  plan:       { ortho: 128, pos: [0, 300, 0], look: [0, 0, 0], up: [0, 0, -1], w: 1600, h: 1600, fog: false, sun: [-120, 200, 90], shadowSpan: 180 },
  aerial_red: { pos: [150, 170, -190], look: [0, 0, -10], fov: 45, fogd: 0.0006, sun: [-120, 200, 90], shadowSpan: 180 },
  aerial_blue:{ pos: [-160, 150, 200], look: [0, 0, 0], fov: 45, fogd: 0.0006, sun: [-120, 200, 90], shadowSpan: 180 },
  courtyard:  { pos: [0, 7, -106], look: [0, 5, -90], fov: 75, sun: [-60, 120, 60], shadowSpan: 140 },
  gateway:    { pos: [0, 6, -92], look: [0, 4, -60], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  square:     { pos: [-22, 7, -76], look: [6, 4, -30], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  alley:      { pos: [-58, 6, -100], look: [-58, 5, -40], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  market:     { pos: [48, 7, -104], look: [80, 4, -50], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  dock:       { pos: [91, 11, -80], look: [55, 3, -50], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  yard:       { pos: [-70, 7, -40], look: [-100, 4, -75], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  quay:       { pos: [-100, 7, -20], look: [0, 4, -5], fov: 65, sun: [-60, 120, 60], shadowSpan: 160 },
  perron:     { pos: [-8, 6, -22], look: [6, 6, 10], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  footbridge: { pos: [-80, 6, -22], look: [-80, 3, 20], fov: 70, sun: [-60, 120, 60], shadowSpan: 140 },
  canal:      { pos: [-100, -1, 0], look: [0, -1, 0], fov: 60, sun: [-60, 120, 60], shadowSpan: 160 },
  estaminet:  { pos: [30.5, 6, -66], look: [40, 3.5, -46], fov: 85, sun: [-60, 120, 60], shadowSpan: 140 },
  atelier:    { pos: [-50, 6, -60], look: [-32, 3.5, -55], fov: 85, sun: [-60, 120, 60], shadowSpan: 140 },
};

if (viewsFile) {
  for (const k of Object.keys(VIEWS)) delete VIEWS[k];
  Object.assign(VIEWS, JSON.parse(fs.readFileSync(viewsFile, 'utf8')));
}

(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  page.on('console', m => console.log('[page]', m.text()));
  page.on('pageerror', e => console.log('[pageerror]', e.message));
  await page.setContent('<html><body style="margin:0;background:#000"><canvas id="c"></canvas></body></html>');
  await page.addScriptTag({ path: threePath });
  await page.evaluate(parts => {
    const P = JSON.parse(parts);
    const scene = new THREE.Scene();
    const sky = new THREE.Color(0xd9c3a5);
    scene.background = sky;
    const renderer = new THREE.WebGLRenderer({ canvas: document.getElementById('c'), antialias: true, preserveDrawingBuffer: true });
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    scene.add(new THREE.HemisphereLight(0xdfe6f2, 0x6a5c50, 0.95));
    const sun = new THREE.DirectionalLight(0xffe0b8, 1.5);
    sun.position.set(-520, 520, 380);
    sun.castShadow = true;
    sun.shadow.mapSize.set(8192, 8192);
    const sc = sun.shadow.camera; sc.left = -760; sc.right = 760; sc.top = 760; sc.bottom = -760; sc.near = 10; sc.far = 2200;
    sun.shadow.bias = -0.0006; sun.shadow.normalBias = 0.6;
    scene.add(sun);
    scene.add(sun.target);

    const boxG = new THREE.BoxGeometry(1, 1, 1);
    const cylG = new THREE.CylinderGeometry(0.5, 0.5, 1, 20); cylG.rotateZ(Math.PI / 2);
    const ballG = new THREE.SphereGeometry(0.5, 16, 12);
    // Roblox wedge: full bottom, full back (+Z) face, slope from top-back down to bottom-front (-Z)
    const wedgeG = new THREE.BufferGeometry();
    const a=[-.5,-.5,-.5], b=[.5,-.5,-.5], c=[.5,-.5,.5], d=[-.5,-.5,.5], e=[-.5,.5,.5], f=[.5,.5,.5];
    const tris = [a,b,c, a,c,d,  d,c,f, d,f,e,  a,e,f, a,f,b,  a,d,e,  b,f,c];
    wedgeG.setAttribute('position', new THREE.Float32BufferAttribute(tris.flat(), 3));
    wedgeG.computeVertexNormals();
    const geo = { Block: boxG, Wedge: wedgeG, Cylinder: cylG, Ball: ballG };
    const mats = new Map();
    const getMat = (p) => {
      const key = p.col.join(',') + '|' + p.t + '|' + (p.m === 'Neon');
      let m = mats.get(key);
      if (!m) {
        const color = new THREE.Color(p.col[0] / 255, p.col[1] / 255, p.col[2] / 255);
        m = p.m === 'Neon' ? new THREE.MeshBasicMaterial({ color })
          : new THREE.MeshLambertMaterial({ color, transparent: p.t > 0, opacity: 1 - p.t, side: THREE.DoubleSide });
        mats.set(key, m);
      }
      return m;
    };
    for (const p of P) {
      if (p.t >= 1) continue;
      const mesh = new THREE.Mesh(geo[p.k], getMat(p));
      let s = p.s;
      if (p.k === 'Cylinder') { const dd = Math.min(s[1], s[2]); s = [s[0], dd, dd]; }
      if (p.k === 'Ball') { const dd = Math.min(s[0], s[1], s[2]); s = [dd, dd, dd]; }
      const c = p.c;
      const m = new THREE.Matrix4().set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
      m.multiply(new THREE.Matrix4().makeScale(s[0], s[1], s[2]));
      mesh.matrixAutoUpdate = false; mesh.matrix.copy(m);
      mesh.castShadow = p.t === 0 && p.m !== 'Neon'; mesh.receiveShadow = true;
      scene.add(mesh);
    }
    window.shoot = (v) => {
      const w = v.w || 1600, h = v.h || 900;
      renderer.setSize(w, h, false);
      let cam;
      if (v.ortho) cam = new THREE.OrthographicCamera(-v.ortho, v.ortho, v.ortho * h / w, -v.ortho * h / w, 1, 3000);
      else cam = new THREE.PerspectiveCamera(v.fov || 60, w / h, 0.5, 3000);
      cam.position.set(...v.pos); if (v.up) cam.up.set(...v.up); cam.lookAt(...v.look);
      if (v.sun) {
        sun.position.set(v.look[0] + v.sun[0], v.look[1] + v.sun[1], v.look[2] + v.sun[2]);
        sun.target.position.set(...v.look);
        const r = v.shadowSpan || 120;
        sc.left = -r; sc.right = r; sc.top = r; sc.bottom = -r; sc.updateProjectionMatrix();
      } else {
        sun.position.set(-520, 520, 380); sun.target.position.set(0, 0, 0);
        sc.left = -760; sc.right = 760; sc.top = 760; sc.bottom = -760; sc.updateProjectionMatrix();
      }
      sun.target.updateMatrixWorld();
      if (v.bg) scene.background = new THREE.Color(v.bg); else scene.background = sky;
      scene.fog = v.fog === false ? null : new THREE.FogExp2(sky, v.fogd || 0.0007);
      renderer.render(scene, cam);
      return document.getElementById('c').toDataURL('image/png');
    };
  }, parts);
  fs.mkdirSync(outDir, { recursive: true });
  for (const [name, v] of Object.entries(VIEWS)) {
    if (only.length && !only.includes(name)) continue;
    const url = await page.evaluate(v => window.shoot(v), v);
    fs.writeFileSync(path.join(outDir, name + '.png'), Buffer.from(url.split(',')[1], 'base64'));
    console.log('wrote', name);
  }
  await browser.close();
})();
