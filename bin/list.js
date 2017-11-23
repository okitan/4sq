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

    return await page.$$eval("table tr", trs => {
      return trs.map(tr => {
        return {
          listName:    tr.querySelectorAll("td")[1].innerText.trim(),
          listAddress: tr.querySelectorAll("td")[0].innerText.trim(),
          listPhone:   tr.querySelectorAll("td")[2].innerText.trim(),
        }
      })
    })
  },
  "グランツリー武蔵小杉": async (page) => {
    await page.goto("http://www.grand-tree.jp/web/shop/index.html", { timeout: 300 * 1000 }) // fucking slow

    return await page.$$eval("#shopList div.item:not(.all)", divs => {
      return divs.map(div => {
        return {
          listName:    div.querySelector(".name").innerText.trim(),
          listAddress: div.querySelector(".floor img").alt.trim(),
        }
      })
    })
  },
  "武蔵小杉東急スクエア": async (page) => {
    let list = []
    for (let i=1; i <=5; i++) {
      await page.goto(`http://www.kosugi-square.com/floor/?fcd=${i}`)
      const crossStreet = `${i}F`

      const shops = await page.$$eval("div.floorlist__txt", divs => {
        return divs.map(div => {
          return {
            listName:  div.querySelector(".floorlist__txt--shopname").innerText.trim(),
            listPhone: div.querySelector(".floorlist__txt--tel").innerText.trim(),
          }
        })
      })
      shops.forEach(e => {
        e.listAddress = crossStreet
        list.push(e)
      })
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
      e.listPhone = findPhoneNumber(e.listPhone)

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

    fs.writeFileSync(file, ltsv.format(results.sort(sortFunction)))

    // console.log(JSON.stringify(results.sort(sortFunction)))
  })()
}
