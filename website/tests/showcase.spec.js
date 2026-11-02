import { test, expect } from '@playwright/test'
import { mkdir } from 'node:fs/promises'

test('showcase works at desktop and phone sizes', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  page.on('response', (response) => {
    if (response.url().startsWith('http://127.0.0.1:4173') && response.status() >= 400) {
      errors.push(`${response.status()} ${response.url()}`)
    }
  })
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Before you go')
  for (const [name, image] of [
    ['Follow the light', '3D Yosemite'],
    ['Choose your moment', 'June 2026'],
    ['Find your position', 'Yosemite map'],
  ]) {
    const button = page.getByRole('button', { name: new RegExp(name) })
    await button.click()
    await expect(button).toHaveAttribute('aria-pressed', 'true')
    await expect(page.getByRole('img', { name: new RegExp(image) })).toBeVisible()
  }
  await page.getByRole('link', { name: 'Get PhotoSim', exact: false }).click()
  await expect(page).toHaveURL(/#download$/)
  await expect(page.getByRole('link', { name: 'Download AppImage' })).toHaveAttribute('href', /\/v1\.1\.1\/PhotoSim-1\.1\.1-x86_64\.AppImage$/)
  await expect(page.getByRole('link', { name: 'Download APK' })).toHaveAttribute('href', /arm64-v8a\.apk$/)
  await expect(page.getByRole('link', { name: /View full-size Android/ })).toHaveCount(3)
  await page.evaluate(async () => {
    for (const image of document.images) image.loading = 'eager'
    await Promise.all([...document.images].map((image) => image.decode()))
    await document.fonts.ready
  })
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.goto('/')
  await page.keyboard.press('Tab')
  await expect(page.getByRole('link', { name: 'Skip to content' })).toBeFocused()
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/#main$/)
  if (process.env.SHOWCASE_CAPTURE) {
    await page.evaluate(async () => {
      for (const image of document.images) image.loading = 'eager'
      await Promise.all([...document.images].map((image) => image.decode()))
      await document.fonts.ready
      window.scrollTo(0, 0)
    })
    await mkdir('../.impeccable/review', { recursive: true })
    await page.screenshot({ path: `../.impeccable/review/${testInfo.project.name}.png`, fullPage: true })
  }
  expect(errors).toEqual([])
})
