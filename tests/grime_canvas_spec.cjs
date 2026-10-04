// Uses the locally installed Grime renderer; never includes it in our package.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const jobs=JSON.parse(fs.readFileSync(path.join(__dirname,'dirt_canvas_jobs.generated.json'),'utf8'));
(async () => {
  const browser = await chromium.launch({channel:'msedge',headless:true});
  try {
    for (const [name,tag] of [['dirt','@dynamic_dirt'],['rough','@dynamic_dirt_rough'],['glass','@dynamic_dirt_glass'],['glassrough','@dynamic_dirt_glass_rough']]) {
      const page = await browser.newPage();
      await page.setContent('<canvas id="c" width="512" height="512"></canvas>');
      await page.evaluate(()=>document.querySelector('canvas').getContext('2d',{willReadFrequently:true}));
      await page.addScriptTag({content:fs.readFileSync(path.join(process.env.GRIME_CANVAS_DIRECTORY,name+'.js'),'utf8')});
      const result = await page.evaluate(async ({name,script}) => {
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
        const apply = () => name.startsWith('glass') ? setGlass({lv:.7,wet:.5,mud:.6,spray:.3})
          : dirt({marks:[{k:1,u:.5,v:.5,l:.8,w:.4,s:1,bx:1,by:0}]});
        apply();await settle();const dirty=pixels();
        washDirt();await settle();const rewound=pixels();
        apply();await settle();const cancelled=pixels();
        washDirt();apply(); // Deliberately leave the old renderer timer pending.
        (0,eval)(script);
        const immediate=pixels();
        await settle();const settled=pixels();
        const preview=[];
        for(let i=0;i<4;i++) { (0,eval)(script);preview.push(pixels());await new Promise(r=>setTimeout(r,25)); }
        return {clean,dirty,rewound,cancelled,immediate,settled,preview};
      },{name,script:jobs[tag]});
      assert.notEqual(result.dirty,result.clean,name+' did not become dirty');
      assert.equal(result.rewound,result.clean,name+' retained future dirt or changed clean paint');
      assert.notEqual(result.cancelled,result.clean,name+' could not restore dirt');
      assert.notEqual(result.immediate,result.clean,name+' exposed clean paint before the redraw timer');
      assert.equal(result.immediate,result.settled,name+' waited for a timer to finish the repaint');
      for(const frame of result.preview) assert.equal(frame,result.settled,name+' flashed between preview frames');
      console.log('GRIME_CANVAS_PASS '+name+' atomic preview stays dirty with old timers pending');
      await page.close();
    }
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
