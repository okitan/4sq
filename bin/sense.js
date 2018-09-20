#!/usr/bin/env node

'use strict';

const puppeteer = require('puppeteer');

const url = process.argv[2];

const findAddress = str => {
  if (str) {
    const mateched = str.match(
      /(...??[都道府県])?((?:旭川|伊達|石狩|盛岡|奥州|田村|南相馬|那須塩原|東村山|武蔵村山|羽村|十日町|上越|富山|野々市|大町|蒲郡|四日市|姫路|大和郡山|廿日市|下松|岩国|田川|大村)市|.+?郡(?:玉村|大町|.+?)[町村]|.+?市.+?区|.+?[市区町村])(.+)/,
    );
  }
  return '';
};

const findPhoneNumber = str => {
  if (str) {
    const matched = str.match(/(\d{2,4})-?(\d{2,4})-?(\d{3,4})/);

    if (matched) {
      return matched.slice(1, 4).join('');
    }
  }
  return '';
};

(async () => {
  const browser = await puppeteer.launch({ headless: process.env.NO_HEADLESS ? false : true });
  const page = await browser.newPage();

  let results = [];
  if ('templates' in config[shop]) {
    for (const template of config[shop].templates) {
      results.push(...(await getShopsWithTemplate(page, template)));
    }
  } else if ('shops' in config[shop]) {
    for (const configShop of config[shop].shops) {
      results.push(...(await getShops(page, configShop)));
    }
  }
  browser.close();

  results.forEach(e => {
    e.closed = false;
  });

  const file = `venues/${shop}.ltsv`;
  try {
    fs.statSync(file);

    const original = ltsv.parse(fs.readFileSync(file));
    original.forEach(originalVenue => {
      const match = results.find(e => e.listName == originalVenue.listName);

      if (match) {
        // replace match one with original one
        Object.assign(originalVenue, match);
        Object.assign(match, originalVenue);
      } else {
        originalVenue.closed = true;

        results.push(originalVenue);
      }
    });
  } catch (err) {
    // Do Nothing
  }

  results.forEach(e => {
    if (!('url' in e)) {
      e.url = '';
    }
  });

  fs.writeFileSync(file, ltsv.format(results.sort(sortFunction)) + '\n');
})();
