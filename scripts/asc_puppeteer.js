/**
 * App Store Connect 自动化脚本
 * 使用 Puppeteer 连接已登录的 Chrome 浏览器
 */
const puppeteer = require('puppeteer');

const DEBUG_PORT = 9222;
const APP_STORE_CONNECT_URL = 'https://appstoreconnect.apple.com';
const DEVELOPER_URL = 'https://developer.apple.com';
const BUNDLE_ID = 'com.evowit.paicc';

async function main() {
    console.log('=== PAI-CC App Store Connect 自动化工具 ===\n');

    // 连接到已运行的 Chrome 实例
    console.log('正在连接到 Chrome...');
    const browser = await puppeteer.connect({
        browserURL: `http://localhost:${DEBUG_PORT}`,
        defaultViewport: null
    });

    console.log('成功连接到 Chrome\n');

    // 获取当前标签页
    const pages = await browser.pages();
    console.log(`当前打开的标签页数: ${pages.length}`);

    // 检查是否已登录 App Store Connect
    let currentPage = pages[0];
    if (!currentPage) {
        currentPage = await browser.newPage();
    }

    console.log('\n=== 检查登录状态 ===');
    await currentPage.goto(APP_STORE_CONNECT_URL, { waitUntil: 'networkidle2' });
    await currentPage.waitForTimeout(2000);

    const currentUrl = currentPage.url();
    console.log(`当前 URL: ${currentUrl}`);

    if (currentUrl.includes('login') || currentUrl.includes('auth')) {
        console.log('❌ 未登录 App Store Connect');
        console.log('请在 Chrome 中手动登录 App Store Connect:');
        console.log('  https://appstoreconnect.apple.com');
        console.log('\n登录后重新运行此脚本');
        await browser.disconnect();
        return;
    }

    console.log('✅ 已登录 App Store Connect\n');

    // 显示操作菜单
    console.log('=== 可用操作 ===');
    console.log('1. 查看证书列表');
    console.log('2. 查看 Provisioning Profiles');
    console.log('3. 下载证书');
    console.log('4. 导航到 PAI-CC App');
    console.log('5. 查看构建版本');
    console.log('6. 退出');

    const args = process.argv.slice(2);
    const action = args[0] || '6';

    switch (action) {
        case '1':
            console.log('\n=== 查看证书列表 ===');
            await currentPage.goto(`${DEVELOPER_URL}/account/resources/certificates`, { waitUntil: 'networkidle2' });
            await currentPage.waitForTimeout(3000);

            // 获取证书列表
            const certCount = await currentPage.evaluate(() => {
                const items = document.querySelectorAll('[data-testid="certificate-item"]');
                return items.length;
            });
            console.log(`找到 ${certCount} 个证书`);
            break;

        case '2':
            console.log('\n=== 查看 Provisioning Profiles ===');
            await currentPage.goto(`${DEVELOPER_URL}/account/resources/profiles`, { waitUntil: 'networkidle2' });
            await currentPage.waitForTimeout(3000);

            // 获取 profiles 列表
            const profileCount = await currentPage.evaluate(() => {
                const items = document.querySelectorAll('[data-testid="profile-item"]');
                return items.length;
            });
            console.log(`找到 ${profileCount} 个 Provisioning Profiles`);
            break;

        case '3':
            console.log('\n=== 下载证书 ===');
            console.log('请在浏览器中手动操作:');
            console.log('1. 前往 https://developer.apple.com/account/resources/certificates');
            console.log('2. 下载 iPhone Distribution 证书');
            console.log('3. 下载 iOS Team Provisioning Profile');
            break;

        case '4':
            console.log('\n=== 导航到 PAI-CC App ===');
            await currentPage.goto(`${APP_STORE_CONNECT_URL}/apps/${BUNDLE_ID}/ios/general`, { waitUntil: 'networkidle2' });
            await currentPage.waitForTimeout(3000);
            console.log('已导航到 PAI-CC App 页面');
            break;

        case '5':
            console.log('\n=== 查看构建版本 ===');
            await currentPage.goto(`${APP_STORE_CONNECT_URL}/apps/${BUNDLE_ID}/ios/builds`, { waitUntil: 'networkidle2' });
            await currentPage.waitForTimeout(3000);
            console.log('已导航到构建版本页面');
            break;

        default:
            console.log('\n退出');
    }

    console.log('\n=== 操作完成 ===');
    console.log('浏览器保持打开状态，请手动完成后续操作');

    // 保持浏览器连接
    await new Promise(resolve => setTimeout(resolve, 60000));
    await browser.disconnect();
}

main().catch(console.error);