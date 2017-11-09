#!/usr/bin/env node

"use strict"

const puppeteer = require('puppeteer')

const ltsv = require("ltsv")
const fs   = require("fs")

const shop = process.argv[2]

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

    return await page.$$eval("table tr", trs => {
      return trs.map(tr => {
        return {
          listName:    tr.querySelectorAll("td")[1].innerText.trim(),
          listAddress: tr.querySelectorAll("td")[0].innerText.trim(),
          closed:      false,
          url:         "",
        }
      })
    })
  }
}

if (shop in map) {
  (async () => {
    const browser    = await puppeteer.launch({ headless: true })
    const page = await browser.newPage()

    const results = await map[shop](page)
    browser.close()

    const file = `venues/${shop}.ltsv`

    try {
      fs.statSync(file)

      const original = ltsv.parse(fs.readFileSync(file))
      original.forEach(e => { e.closed = true })

      original.forEach(originalVenue => {
        const match = results.find(e => e.listName == originalVenue.listName)

        if (match) {
          // replace match one with original one
          Object.assign(match, originalVenue, { closed: false })
        } else {
          results.push(originalVenue)
        }
      })
    } catch (err) {
      // Do Nothing
    }

    fs.writeFileSync(file, ltsv.format(results.sort(sortFunction)))

    // console.log(JSON.stringify(results.sort(sortFunction)))

  })()
}
