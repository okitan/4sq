#!/usr/bin/env node

"use strict"

const puppeteer = require('puppeteer')

const yaml = require('js-yaml')
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

const config = yaml.safeLoad(fs.readFileSync("./config/venues.yaml"))

const map = {
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

const getShops = async (page, shopConfig) => {
  const results = []
  for (const [ url, selectorMap ] of Object.entries(shopConfig)) {
    await page.goto(url, { timeout: 300 * 1000 }) //グランツリー武蔵小杉 is too slow

    for (const [ selector, attributeMap ] of Object.entries(selectorMap)) {
      const shops = await page.$$(selector)

      results.push(...await Promise.all(shops.map(async shop => {
        const result = {}
        for (const attribute of [ "listName", "listAddress", "listPhone" ]) {
          if (attribute in attributeMap) {
            let propertySelector, property

            if (typeof attributeMap[attribute] == "string") {
              propertySelector = attributeMap[attribute]
              property = "textContent"
            } else {
              ({ propertySelector, property } = attributeMap[attribute])
            }
            let value = (await shop.$(propertySelector).then(e => e.getProperty(property)).then(e => e.jsonValue())).trim()

            if (attribute == "listPhone") {
              value = findPhoneNumber(value)
            }

            result[attribute] = value
          }
        }
        return result
      })))
    }
  }
  return results
}

if (shop in config || shop in map) {
  (async () => {
    const browser = await puppeteer.launch({ headless: (process.env.NO_HEADLESS ? false : true) })
    const page    = await browser.newPage()

    let results
    if (shop in config && "shops" in config[shop]) {
      results = await getShops(page, config[shop].shops)
    } else {
      results = await map[shop](page)
    }
    browser.close()

    results.forEach(e => {
      e.closed = false
    })

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
