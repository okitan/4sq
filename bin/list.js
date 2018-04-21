#!/usr/bin/env node

'use strict';

const puppeteer = require('puppeteer');

const { render } = require('mustache');
const yaml = require('js-yaml');
const ltsv = require('ltsv');
const fs = require('fs');

const shop = process.argv[2];

const findPhoneNumber = str => {
  if (str) {
    const matched = str.match(/(\d{2,4})-?(\d{2,4})-?(\d{3,4})/);

    if (matched) {
      return matched.slice(1, 4).join('');
    }
  }
  return '';
};

const sortFunction = (a, b) => {
  if (a.listAddress < b.listAddress) {
    return -1;
  } else if (a.listAddress > b.listAddress) {
    return 1;
  }
  if (a.listName < b.listName) {
    return -1;
  } else if (a.listName > b.listName) {
    return 1;
  }
  return 0;
};

const config = yaml.safeLoad(fs.readFileSync('./config/venues.yaml'));

const getShopsWithTemplate = async (page, { items, shops: shopTemplate }) => {
  let results = [];
  for (const item of items) {
    const shopConfig = {};

    // make config from template
    shopConfig.url = render(shopTemplate.url, { item: item }); // TODO: resolve mustache
    shopConfig.selector = shopTemplate.selector;
    shopConfig.attributes = {};
    for (const attribute of ['listName', 'listAddress', 'listPhone']) {
      if (attribute in shopTemplate.attributes) {
        if (typeof shopTemplate.attributes[attribute] === 'string') {
          shopConfig.attributes[attribute] = render(shopTemplate.attributes[attribute], { item: item });
        } else {
          shopConfig.attributes[attribute] = shopTemplate.attributes[attribute];
        }
      }
    }

    results.push(...(await getShops(page, shopConfig)));
  }
  return results;
};

const getShops = async (page, { url, selector, attributes }) => {
  await page.goto(url, { timeout: 300 * 1000 }); //グランツリー武蔵小杉 is too slow

  const shops = await page.$$(selector);

  return Promise.all(
    shops.map(async shop => {
      const result = {};
      for (const attribute of ['listName', 'listAddress', 'listPhone']) {
        if (attribute in attributes) {
          let value;
          if (typeof attributes[attribute] === 'object') {
            let { propertySelector, property } = attributes[attribute];
            property = property || 'innerText';

            value = (await (await (await shop.$(propertySelector)).getProperty(property)).jsonValue())
              .trim()
              .replace(/[Ａ-Ｚａ-ｚ０-９]/g, function(s) {
                // https://qiita.com/yamikoo@github/items/5dbcc77b267a549bdbae
                return String.fromCharCode(s.charCodeAt(0) - 0xfee0);
              });
          } else {
            value = attributes[attribute];
          }

          if (attribute == 'listPhone') {
            value = findPhoneNumber(value);
          }

          result[attribute] = value;
        } else {
          result[attribute] = '';
        }
      }
      return result;
    }),
  );
};

if (shop in config) {
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
}
