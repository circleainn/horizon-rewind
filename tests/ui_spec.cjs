const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const game = process.env.BEAMNG_ROOT || 'C:/Steam/steamapps/common/BeamNG.drive';
(async () => {
  const browser = await chromium.launch({channel:'msedge',headless:true});
  try {
    const page = await browser.newPage({viewport:{width:600,height:330}});
    await page.route('http://rewind.test/', route => route.fulfill({contentType:'text/html',body:'<body style="background:#555"><div id="app" style="width:360px;height:180px"><horizon-rewind></horizon-rewind></div></body>'}));
    async function mount() {
      await page.goto('http://rewind.test/');
      await page.addScriptTag({path:path.join(game,'ui/lib/ext/angular/angular.js')});
      await page.evaluate(()=>{window.commands=[];window.bngApi={engineLua:c=>commands.push(c)};angular.module('beamng.apps',[]);});
      await page.addScriptTag({path:path.join(root,'mod/ui/modules/apps/HorizonRewind/app.js')});
      await page.evaluate(html=>{
        angular.module('beamng.apps').run(['$templateCache',cache=>cache.put('/ui/modules/apps/HorizonRewind/app.html',html)]);
        angular.bootstrap(document.getElementById('app'),['beamng.apps']);
        const scope=angular.element(document.getElementById('app')).injector().get('$rootScope');
        scope.$broadcast('HorizonRewindState',{enabled:true,phase:'recording',availableSeconds:15,maxSeconds:20,speed:2});scope.$digest();
      },fs.readFileSync(path.join(root,'mod/ui/modules/apps/HorizonRewind/app.html'),'utf8'));
    }
    await mount();
    for(const width of [320,360]) {
      await page.locator('#app').evaluate((e,w)=>e.style.width=w+'px',width);
      for(const speed of [0.25,0.5,1,2,4,8]) {
        await page.getByRole('button',{name:'Rewind speed',exact:true}).click();
        const menu=page.getByRole('menu');assert(await menu.isVisible());
        const bounds=await menu.boundingBox(),parent=await page.locator('#app').boundingBox();
        assert(bounds.x>=parent.x && bounds.y>=parent.y && bounds.x+bounds.width<=parent.x+parent.width,'Menu clipped');
        await page.getByRole('menuitemradio',{name:speed+'×',exact:true}).click();
        assert(await page.evaluate(s=>commands.some(c=>c.includes('setSpeed('+s+')')),speed));
        assert(!(await menu.isVisible()));
      }
    }
    const speedButton=page.getByRole('button',{name:'Rewind speed',exact:true});
    await speedButton.focus();await page.keyboard.press('ArrowDown');
    await page.waitForFunction(()=>document.activeElement.getAttribute('role')==='menuitemradio');
    await page.keyboard.press('Enter');
    assert(await page.evaluate(()=>commands.at(-1).includes('setSpeed(0.25)')));
    await speedButton.click();await page.keyboard.press('Escape');await page.getByRole('menu').waitFor({state:'hidden'});
    await speedButton.click();await page.locator('.hr-title').click();await page.getByRole('menu').waitFor({state:'hidden'});
    await page.getByRole('button',{name:'Minimize Horizon Rewind',exact:true}).click();
    assert(!(await page.locator('.hr-body').isVisible()));
    assert.equal(await page.locator('.hr-app').evaluate(e=>getComputedStyle(e).pointerEvents),'none');
    await page.getByRole('button',{name:'Hide Horizon Rewind',exact:true}).click();
    assert(await page.getByRole('button',{name:'Show Horizon Rewind',exact:true}).isVisible());
    await mount();assert(await page.getByRole('button',{name:'Show Horizon Rewind',exact:true}).isVisible());
    await page.getByRole('button',{name:'Show Horizon Rewind',exact:true}).click();
    const hold=page.getByRole('button',{name:'Hold to rewind; release to resume',exact:true});
    await hold.focus();await page.keyboard.down('Enter');
    await page.evaluate(()=>angular.element(document.querySelector('.hr-app')).scope().$apply(s=>s.hrSetView('hidden')));
    await page.keyboard.up('Enter');
    assert(await page.evaluate(()=>commands.filter(c=>c.includes('endRewind()')).length===1),'Hidden hold not released exactly once');
    await page.getByRole('button',{name:'Show Horizon Rewind',exact:true}).click();
    await speedButton.click();
    fs.mkdirSync(path.join(root,'.test-results'),{recursive:true});
    await page.locator('#app').screenshot({path:path.join(root,'.test-results/ui-menu.png')});
    console.log('UI_SPEC_PASSED: six speeds at two widths, keyboard, dismissal, minimize, hide, persistence, held-input cleanup');
  } finally {await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
