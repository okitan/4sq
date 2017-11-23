#!/usr/bin/env node

"use strict"

const puppeteer = require('puppeteer')

const ltsv = require("ltsv")
const fs   = require("fs")

const shop = process.argv[2]

const findPhoneNumber = (str) => {
  if (str) {
    const matched = str.match(/(\d{2,4})-?(\d{2,4})-?(\d{3,4})/)

    if (matched) {
      return matched.slice(1,4).join("")
    }
  }
  return ""
}

const sortFunction = (a, b) => {
  if (a.listAddress < b.listAddress) {
    return -1
  } else if (a.listAddress > b.listAddress) {
      return 1
  }
  if (a.listName < b.listName) {
    return -1
  } else if (a.listName > b.listName) {
    return 1
  }
  return 0
}

const map = {
  "ららテラス武蔵小杉": async (page) => {
    await page.goto("http://www.lalaterrace-musashikosugi.com/floor/floorall")

    const shops = await page.$$("table tr")
    return await Promise.all(shops.map(async shop => {
      return {
        listName:    (await shop.$("td.shopName").then(e   => e.getProperty("textContent")).then(e => e.jsonValue())).trim(),
        listAddress: (await shop.$("td.shopNumber").then(e => e.getProperty("textContent")).then(e => e.jsonValue())).trim(),
        listPhone: findPhoneNumber((await shop.$("td.shopTel").then(e  => e.getProperty("textContent")).then(e => e.jsonValue()))),
      }
    }))
  },
  "グランツリー武蔵小杉": async (page) => {
    await page.goto("http://www.grand-tree.jp/web/shop/index.html", { timeout: 300 * 1000 }) // fucking slow

    const shops = await page.$$("#shopList div.item:not(.all)")

    return await Promise.all(shops.map(async shop => {
      return {
        listName:    (await shop.$(".name").then(e => e.getProperty("textContent")).then(e => e.jsonValue())).trim(),
        listAddress: (await shop.$(".floor img").then(e => e.getProperty("alt")).then(e => e.jsonValue())).trim(),
      }
    }))
  },
  "武蔵小杉東急スクエア": async (page) => {
    let list = []
    for (let i=1; i <=5; i++) {
      await page.goto(`http://www.kosugi-square.com/floor/?fcd=${i}`)
      const crossStreet = `${i}F`

      const shops = await page.$$("div.floorlist__txt")

      list.push(...await Promise.all(shops.map(async shop => {
        return {
          listName:    (await shop.$(".floorlist__txt--shopname").then(e   => e.getProperty("textContent")).then(e => e.jsonValue())).trim(),
          listAddress: crossStreet,
          listPhone: findPhoneNumber((await shop.$(".floorlist__txt--tel").then(e  => e.getProperty("textContent")).then(e => e.jsonValue()))),
        }
      })))
    }
    return list
  }
}

if (shop in map) {
  (async () => {
    const browser = await puppeteer.launch({ headless: (process.env.NO_HEADLESS ? false : true) })
    const page    = await browser.newPage()

    const results = await map[shop](page)
    results.forEach(e => {
      e.closed = false
    })
    browser.close()

    const file = `venues/${shop}.ltsv`

    try {
      fs.statSync(file)

      const original = ltsv.parse(fs.readFileSync(file))
      original.forEach(originalVenue => {
        const match = results.find(e => e.listName == originalVenue.listName)

        if (match) {
          // replace match one with original one
          Object.assign(originalVenue, match)
          Object.assign(match, originalVenue)
        } else {
          originalVenue.closed = true

          results.push(originalVenue)
        }
      })
    } catch (err) {
      // Do Nothing
    }

    results.forEach(e => {
      if (!("url" in e)) {
        e.url = ""
      }
    })

    fs.writeFileSync(file, ltsv.format(results.sort(sortFunction)) + "\n")
  })()
}
