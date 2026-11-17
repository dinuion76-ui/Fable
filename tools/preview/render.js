// Renders build/parts.json with three.js in headless Chromium (a rough stand-in for Studio).
// usage: node render.js <three.min.js> <outDir> [viewName ...]
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const threePath = process.argv[2];
const outDir = process.argv[3];
const only = process.argv.slice(4);
const parts = fs.readFileSync(path.join(__dirname, '../../build/parts.json'), 'utf8');

const VIEWS = {
  plan:      { ortho: 520, pos: [0, 600, 0], look: [0, 0, 0], up: [0, 0, -1], w: 1800, h: 1800, fog: false },
  aerial_se: { pos: [520, 420, 620], look: [-40, 0, -40], fov: 42, fogd: 0.0004 },
  aerial_nw: { pos: [-560, 330, -560], look: [0, 0, 20], fov: 45, fogd: 0.0004 },
  halle:     { pos: [100, 7, -190], look: [40, 9, -230], fov: 70 },
  marche:    { pos: [-232, 7, -124], look: [-150, 14, -80], fov: 70 },
  bueren:    { pos: [-222, 6, -180], look: [-330, 40, -180], fov: 70 },
  horschateau: { pos: [-226, 6, -150], look: [-226, 14, -400], fov: 70 },
  quay:      { pos: [100, 6, -150], look: [110, 8, -420], fov: 70 },
  bridge:    { pos: [96, 8, 40], look: [300, 14, -70], fov: 65 },
  river:     { pos: [170, -5, 120], look: [170, 4, -200], fov: 70 },
  outremeuse:{ pos: [353, 6, -90], look: [353, 12, -400], fov: 70 },
  citadel:   { pos: [-404, 84, -230], look: [100, 0, -60], fov: 70 },
  palace:    { pos: [-380, 6, 40], look: [-450, 12, -40], fov: 75 },
  cathedral: { pos: [-150, 7, 176], look: [-280, 40, 280], fov: 70 },
  station:   { pos: [270, 8, 330], look: [400, 10, 450], fov: 70 },
  foundry:   { pos: [386, 6, 88], look: [460, 8, 80], fov: 80 },
  atelier:   { pos: [370, 6, -148], look: [408, 5, -150], fov: 85 },
  proof:     { pos: [410, 6, -350], look: [465, 4, -360], fov: 85 },
  nave:      { pos: [-282, 7, 281], look: [-120, 12, 281], fov: 75 },
  passage:   { pos: [-90, 6, 102], look: [-10, 10, 102], fov: 70 },
  yards:     { pos: [-158, 6, -440], look: [-158, 6, -200], fov: 70 },
  watergate: { pos: [104, 9, -400], look: [175, 8, -482], fov: 70 },
  citadel_in: { pos: [-470, 71, -150], look: [-410, 70, -300], fov: 70 },
  bueren_side: { pos: [-290, 70, -110], look: [-322, 30, -185], fov: 70 },
  wallwalk:  { pos: [96, 29, -478], look: [230, 22, -482], fov: 75 },
  rail:      { pos: [-60, 8, 437], look: [200, 6, 455], fov: 70 },
  coalyard:  { pos: [372, 8, 240], look: [450, 4, 252], fov: 75 },
  degres:    { pos: [-236, 6, -90], look: [-380, 50, -90], fov: 70 },
  estaminet: { pos: [240, 6, 30], look: [290, 8, 36], fov: 75 },
  stlambert: { pos: [-205, 8, 100], look: [-340, 14, -10], fov: 70 },
};

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
