pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Exchange rates against USD: fiat daily from open.er-api.com, crypto from CoinGecko, cached in the state dir
Singleton {
    id: root

    readonly property var rates: Object.assign({}, adapter.rates, adapter.crypto)
    // Ticker -> CoinGecko id
    readonly property var coins: ({
        BTC: "bitcoin", ETH: "ethereum", TON: "the-open-network", SOL: "solana", USDT: "tether",
        USDC: "usd-coin", BNB: "binancecoin", XRP: "ripple", DOGE: "dogecoin", ADA: "cardano",
        TRX: "tron", LTC: "litecoin", XMR: "monero", DOT: "polkadot", NOT: "notcoin"
    })
    readonly property real updated: adapter.updated
    property bool loading: false
    property bool cryptoLoading: false

    function convert(amount, from, to) {
        const a = rates[from], b = rates[to];
        return a && b ? amount / a * b : NaN;
    }

    function get(url, done) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let data = {};
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {}
            done(data);
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function refresh() {
        if (!loading && Date.now() - adapter.fetched > 6 * 3600000) {
            loading = true;
            get("https://open.er-api.com/v6/latest/USD", data => {
                root.loading = false;
                if (data.result !== "success")
                    return;
                adapter.rates = data.rates;
                adapter.updated = data.time_last_update_unix * 1000;
                adapter.fetched = Date.now();
            });
        }
        // Crypto moves fast, so it's refreshed far more often
        if (!cryptoLoading && (Date.now() - adapter.cryptoFetched > 10 * 60000 || !Object.keys(adapter.crypto).length)) {
            cryptoLoading = true;
            const ids = Object.values(coins);
            get(`https://api.coingecko.com/api/v3/simple/price?vs_currencies=usd&ids=${ids.join(",")}`, data => {
                root.cryptoLoading = false;
                const crypto = {};
                for (const ticker in coins) {
                    const usd = data[coins[ticker]]?.usd;
                    if (usd)
                        crypto[ticker] = 1 / usd;
                }
                // A rate-limit reply has no prices; the old ones are better than none
                if (!Object.keys(crypto).length)
                    return;
                adapter.crypto = crypto;
                adapter.cryptoFetched = Date.now();
            });
        }
    }

    FileView {
        path: Quickshell.statePath("rates.json")
        blockLoading: true
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: adapter
            property var rates: ({})
            property real updated: 0
            property real fetched: 0
            property var crypto: ({})
            property real cryptoFetched: 0
        }
    }
}
