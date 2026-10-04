// Uses the locally installed Grime renderer; never includes it in our package.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
(async () => {
  const browser = await chromium.launch({channel:'msedge',headless:true});
  try {
    for (const name of ['dirt','rough','glass']) {
      const page = await browser.newPage();
      await page.setContent('<canvas id="c" width="512" height="512"></canvas>');
      await page.addScriptTag({content:fs.readFileSync(path.join(process.env.GRIME_CANVAS_DIRECTORY,name+'.js'),'utf8')});
      const result = await page.evaluate(async name => {
        const settle = () => new Promise(resolve=>setTimeout(resolve,400));
        const pixels = () => {
          const bytes=document.querySelector('canvas').getContext('2d').getImageData(0,0,512,512).data;
          let hash=2166136261;
          for (const value of bytes) hash=Math.imul(hash^value,16777619);
          return hash>>>0;
        };
        if(name==='dirt') setPaint({r:60,g:90,b:130});
        if(name==='rough' && window.setPaintFinish) setPaintFinish({roughness:.82});
        washDirt();await settle();const clean=pixels();
        const apply = () => name==='glass' ? setGlass({lv:.7,wet:.5,mud:.6,spray:.3})
          : dirt({marks:[{k:1,u:.5,v:.5,l:.8,w:.4,s:1,bx:1,by:0}]});
        apply();await settle();const dirty=pixels();
        washDirt();await settle();const rewound=pixels();
        apply();await settle();const cancelled=pixels();
        return {clean,dirty,rewound,cancelled};
      },name);
      assert.notEqual(result.dirty,result.clean,name+' did not become dirty');
      assert.equal(result.rewound,result.clean,name+' retained future dirt or changed clean paint');
      assert.notEqual(result.cancelled,result.clean,name+' could not restore dirt');
      console.log('GRIME_CANVAS_PASS '+name+' clean/dirty/rewound/cancelled');
      await page.close();
    }
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
