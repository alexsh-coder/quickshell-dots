pragma Singleton

import QtQuick
import Quickshell

// Launcher answers that need no network round trip of their own:
// "=2+2", "sqrt(2)*pi", "100 usd", "0.5 btc в руб", "10 km in mi", "30c", "через 100 дней", "до 31.12"
Singleton {
    id: root

    readonly property var consts: ({ pi: Math.PI, "π": Math.PI, e: Math.E, tau: 2 * Math.PI })
    readonly property var funcs: ({
        sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, exp: Math.exp,
        ln: Math.log, log: Math.log10, lg: Math.log10, log2: Math.log2,
        sin: Math.sin, cos: Math.cos, tan: Math.tan, tg: Math.tan,
        asin: Math.asin, acos: Math.acos, atan: Math.atan,
        round: Math.round, floor: Math.floor, ceil: Math.ceil,
        min: Math.min, max: Math.max, pow: Math.pow
    })

    // A trailing "*" matches by prefix, so declensions like "долларов" or "рублей" work too
    readonly property var aliases: [
        ["$", "USD"], ["долл*", "USD"], ["бакс*", "USD"], ["dollar*", "USD"],
        ["€", "EUR"], ["евро", "EUR"], ["euro*", "EUR"],
        ["₽", "RUB"], ["руб*", "RUB"], ["р", "RUB"], ["р.", "RUB"], ["ruble*", "RUB"], ["rouble*", "RUB"],
        ["£", "GBP"], ["фунт*", "GBP"], ["pound*", "GBP"],
        ["¥", "CNY"], ["юан*", "CNY"], ["yuan", "CNY"], ["иен*", "JPY"], ["йен*", "JPY"], ["yen", "JPY"],
        ["₸", "KZT"], ["тенге", "KZT"], ["₴", "UAH"], ["гривн*", "UAH"],
        ["₺", "TRY"], ["лир*", "TRY"], ["франк*", "CHF"], ["злот*", "PLN"], ["драм*", "AMD"], ["лари", "GEL"],
        ["₿", "BTC"], ["биткоин*", "BTC"], ["биток*", "BTC"], ["bitcoin*", "BTC"], ["сат*", "SAT"], ["sat", "SAT"], ["sats", "SAT"],
        ["эфир*", "ETH"], ["ether*", "ETH"], ["тон", "TON"], ["тонкоин*", "TON"], ["toncoin", "TON"],
        ["солан*", "SOL"], ["тезер*", "USDT"], ["доге*", "DOGE"], ["монеро", "XMR"], ["лайткоин*", "LTC"]
    ]

    // name -> [dimension, factor to the base unit, display name]; temperature is special-cased
    readonly property var units: {
        const u = {};
        const add = (dim, factor, shown, ...names) => names.forEach(n => u[n] = [dim, factor, shown]);
        add("len", 0.001, "mm", "mm", "мм", "millimeter*", "миллиметр*");
        add("len", 0.01, "cm", "cm", "см", "centimeter*", "сантиметр*");
        add("len", 1, "m", "m", "м", "meter*", "metre*", "метр*");
        add("len", 1000, "km", "km", "км", "kilometer*", "kilometre*", "километр*");
        add("len", 0.0254, "in", "in", "inch*", "дюйм*", "\"");
        add("len", 0.3048, "ft", "ft", "foot", "feet", "фут*");
        add("len", 0.9144, "yd", "yd", "yard*", "ярд*");
        add("len", 1609.344, "mi", "mi", "mile*", "мил*");
        add("len", 1852, "nmi", "nmi", "морск*");
        add("mass", 1e-6, "mg", "mg", "мг");
        add("mass", 0.001, "g", "g", "г", "gram*", "грам*");
        add("mass", 1, "kg", "kg", "кг", "kilo*", "килограм*");
        add("mass", 1000, "t", "t", "т", "tonne*", "тонн*");
        add("mass", 0.0283495, "oz", "oz", "ounce*", "унци*");
        add("mass", 0.453592, "lb", "lb", "lbs");
        add("mass", 6.35029, "st", "st", "stone*");
        add("vol", 0.001, "ml", "ml", "мл");
        add("vol", 1, "l", "l", "л", "liter*", "litre*", "литр*");
        add("vol", 1000, "m³", "m3", "м3", "m³", "м³");
        add("vol", 0.00492892, "tsp", "tsp", "ч.л.");
        add("vol", 0.0147868, "tbsp", "tbsp", "ст.л.");
        add("vol", 0.236588, "cup", "cup*", "стакан*");
        add("vol", 0.0295735, "fl oz", "floz");
        add("vol", 0.473176, "pt", "pt", "pint*", "пинт*");
        add("vol", 3.78541, "gal", "gal", "gallon*", "галлон*");
        add("area", 1e-4, "cm²", "cm2", "см2", "cm²", "см²");
        add("area", 1, "m²", "m2", "м2", "m²", "м²", "sqm");
        add("area", 1e6, "km²", "km2", "км2", "km²", "км²");
        add("area", 1e4, "ha", "ha", "га", "hectare*", "гектар*");
        add("area", 100, "сотка", "сот*");
        add("area", 4046.86, "acre", "acre*", "акр*");
        add("area", 0.092903, "ft²", "ft2", "sqft", "ft²");
        add("speed", 1, "m/s", "m/s", "м/с", "mps");
        add("speed", 1 / 3.6, "km/h", "km/h", "км/ч", "kmh", "kph");
        add("speed", 0.44704, "mph", "mph", "mi/h");
        add("speed", 0.514444, "kn", "kn", "knot*", "узл*", "узел");
        add("data", 0.125, "bit", "bit*", "бит*");
        add("data", 125, "kbit", "kbit*", "kb/s", "кбит*");
        add("data", 125000, "Mbit", "mbit*", "mbps", "мбит*");
        add("data", 125000000, "Gbit", "gbit*", "gbps", "гбит*");
        add("data", 1, "B", "byte*", "байт*");
        add("data", 1e3, "KB", "kb", "кб");
        add("data", 1e6, "MB", "mb", "мб");
        add("data", 1e9, "GB", "gb", "гб");
        add("data", 1e12, "TB", "tb", "тб");
        add("data", 1024, "KiB", "kib");
        add("data", 1048576, "MiB", "mib");
        add("data", 1073741824, "GiB", "gib");
        add("data", 1099511627776, "TiB", "tib");
        add("time", 0.001, "ms", "ms", "мс");
        add("time", 1, "s", "s", "sec*", "second*", "сек*");
        add("time", 60, "min", "min", "mins", "minute*", "мин*");
        add("time", 3600, "h", "h", "hr", "hrs", "hour*", "ч", "час*");
        add("time", 86400, "d", "d", "day*", "дн*", "день", "сут*");
        add("time", 604800, "wk", "w", "wk", "week*", "нед*");
        add("time", 2629746, "mo", "mo", "month*", "мес*");
        add("time", 31556952, "yr", "y", "yr", "year*", "год*", "лет");
        add("temp", 0, "°C", "c", "°c", "°", "celsius", "цельс*", "°ц");
        add("temp", 0, "°F", "f", "°f", "fahrenheit", "фаренг*", "°ф");
        add("temp", 0, "K", "k", "kelvin*", "кельвин*");
        return u;
    }
    // Where a lone unit converts to
    readonly property var pairs: ({
        mm: "in", cm: "in", m: "ft", km: "mi", in: "cm", ft: "m", yd: "m", mi: "km", nmi: "km",
        mg: "g", g: "oz", kg: "lb", t: "lb", oz: "g", lb: "kg", st: "kg",
        ml: "fl oz", l: "gal", "m³": "l", tsp: "ml", tbsp: "ml", cup: "ml", "fl oz": "ml", pt: "l", gal: "l",
        "cm²": "m²", "m²": "ft²", "km²": "ha", ha: "acre", "сотка": "m²", acre: "ha", "ft²": "m²",
        "m/s": "km/h", "km/h": "mph", mph: "km/h", kn: "km/h",
        bit: "B", kbit: "KB", Mbit: "MB", Gbit: "GB", B: "bit", KB: "KiB", MB: "MiB", GB: "GiB", TB: "TiB",
        KiB: "KB", MiB: "MB", GiB: "GB", TiB: "TB",
        ms: "s", s: "min", min: "s", h: "min", d: "h", wk: "d", mo: "d", yr: "d",
        "°C": "°F", "°F": "°C", K: "°C"
    })
    readonly property var connectors: ["to", "in", "into", "в", "во", "на", "->", "→", "="]

    readonly property string ruKeys: "йцукенгшщзхъфывапролджэячсмитьбю"
    readonly property string enKeys: "qwertyuiop[]asdfghjkl;'zxcvbnm,."

    // null when the query isn't a calculation; { text, copy, hint, icon } otherwise
    function answer(query) {
        let q = query.trim().toLowerCase();
        const forced = q.startsWith("=");
        if (forced)
            q = q.slice(1).trim();
        if (!q)
            return null;
        const hit = date(q) ?? convert(q);
        if (hit)
            return hit;
        // Without "=" only plain arithmetic counts, so app names never turn into math
        if (!forced && (!/^[\d\s.,+\-*/^()%×÷·!]+$/.test(q) || !/\d.*[+\-*/^%×÷·!]|[+\-*/^%×÷·!].*\d/.test(q)))
            return null;
        const v = evaluate(q);
        if (!isFinite(v))
            return null;
        return { text: format(v, 10), copy: plain(v, 10), hint: q, icon: "calculate" };
    }

    function matchWord(word, list) {
        return list.find(([a]) => a.endsWith("*") ? word.startsWith(a.slice(0, -1)) : word === a);
    }

    function swapLayout(word) {
        return [...word].map(c => {
            const i = ruKeys.indexOf(c);
            return i < 0 ? c : enKeys[i];
        }).join("");
    }

    // { cur: "USD" } or { unit: [dim, factor, shown] } or null
    function measure(word) {
        if (!word)
            return null;
        const unitHit = Object.keys(units).find(n => n.endsWith("*") ? word.startsWith(n.slice(0, -1)) : word === n);
        if (unitHit)
            return { unit: units[unitHit] };
        const rates = Rates.rates;
        const code = word.toUpperCase();
        if (/^[A-Z]{3,5}$/.test(code) && (rates[code] || Rates.coins[code]))
            return { cur: code };
        // "гыв" is "usd" typed on the RU layout
        const swapped = swapLayout(word).toUpperCase();
        if (/^[A-Z]{3,5}$/.test(swapped) && (rates[swapped] || Rates.coins[swapped]))
            return { cur: swapped };
        const alias = matchWord(word, aliases);
        return alias ? { cur: alias[1] } : null;
    }

    function convert(q) {
        // Signs become separate words ("100$" -> "100 $"), so do units glued to the number ("10km")
        const words = q.replace(/([$€₽£¥₸₴₺₿])/g, " $1 ").replace(/(\d)([a-zа-яё°"])/g, "$1 $2").trim().split(/\s+/);
        if (words.length < 2)
            return null;
        // "$100" -> "100 $"
        if (measure(words[0])?.cur && !/\d/.test(words[0]))
            words.push(words.shift());
        const found = [];
        let linked = false;
        while (words.length > 1) {
            const w = words[words.length - 1];
            // Right after the target, "in" is a connector, not inches
            if (found.length === 1 && !linked && connectors.includes(w)) {
                linked = true;
                words.pop();
                continue;
            }
            const m = measure(w);
            // Money and units don't mix: "5k usd" is thousands of dollars, not kelvins
            if (m && found.length && !m.cur !== !found[0].cur)
                break;
            if (m)
                found.unshift(m);
            else if (!connectors.includes(w) || !found.length)
                break;
            words.pop();
        }
        // "5к" / "5k" thousands, "2м" / "2m" millions, but only next to money
        let expr = words.join(" ");
        if (found[0]?.cur)
            expr = expr.replace(/(\d)\s*[kк]$/, "$1*1000").replace(/(\d)\s*[mм]$/, "$1*1000000");
        if (!found.length || found.length > 2 || !/\d/.test(expr))
            return null;
        const amount = evaluate(expr);
        if (!isFinite(amount))
            return null;
        return found[0].cur ? money(amount, found) : unit(amount, found);
    }

    function money(amount, found) {
        if (found[1] && !found[1].cur)
            return null;
        Rates.refresh();
        const rates = Object.assign({ SAT: (Rates.rates.BTC ?? NaN) * 1e8 }, Rates.rates);
        let from = found[0].cur;
        const crypto = Rates.coins[from] || from === "SAT";
        const to = found[1]?.cur ?? (crypto ? "USD" : from === "RUB" ? "USD" : "RUB");
        if (!rates[from] || !rates[to])
            return Rates.loading || !Object.keys(Rates.rates).length
                ? { text: "…", copy: "", hint: "Loading exchange rates", icon: "currency_exchange" }
                : null;
        const v = amount / rates[from] * rates[to];
        const rate = 1 / rates[from] * rates[to];
        const date = new Date(Rates.updated).toLocaleDateString(Qt.locale(), "d MMM");
        return {
            text: `${money2(v)} ${to}`,
            copy: plain(v, decimals(v)),
            hint: `${money2(amount)} ${from}  ·  1 ${from} = ${money2(rate)} ${to}` + (crypto || Rates.coins[to] ? "  ·  live" : `  ·  ${date}`),
            icon: crypto || Rates.coins[to] ? "currency_bitcoin" : "currency_exchange"
        };
    }

    function unit(amount, found) {
        const [dim, factor, shown] = found[0].unit;
        let target = found[1]?.unit;
        if (!target) {
            const name = pairs[shown];
            target = Object.values(units).find(u => u[2] === name);
        }
        if (!target || target[0] !== dim)
            return null;
        const v = dim === "temp" ? temperature(amount, shown, target[2]) : amount * factor / target[1];
        return {
            text: `${format(v, decimals(v))} ${target[2]}`,
            copy: plain(v, decimals(v)),
            hint: `${format(amount, 6)} ${shown}`,
            icon: { len: "straighten", mass: "scale", vol: "water_drop", area: "square_foot", speed: "speed", data: "storage", time: "schedule", temp: "thermostat" }[dim]
        };
    }

    function temperature(v, from, to) {
        const c = from === "°F" ? (v - 32) * 5 / 9 : from === "K" ? v - 273.15 : v;
        return to === "°F" ? c * 9 / 5 + 32 : to === "K" ? c + 273.15 : c;
    }

    // "через 100 дней", "in 3 weeks", "+10d", "до 31.12", "until 2027-01-01", "до нг"
    function date(q) {
        const step = q.match(/^(?:через|in|\+)\s*(\d+)\s*(d|days?|дн\S*|день|w|weeks?|нед\S*|months?|мес\S*|y|years?|год\S*|лет)$/)
            ?? q.match(/^(\d+)\s*(days?|дн\S*|день|weeks?|недел\S*)$/);
        const day = 86400000;
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        if (step) {
            const n = parseInt(step[1]);
            const u = step[2];
            const d = new Date(today);
            if (/^(d|day|дн|день)/.test(u)) d.setDate(d.getDate() + n);
            else if (/^(w|нед)/.test(u)) d.setDate(d.getDate() + 7 * n);
            else if (/^(mo|мес)/.test(u)) d.setMonth(d.getMonth() + n);
            else d.setFullYear(d.getFullYear() + n);
            return {
                text: d.toLocaleDateString(Qt.locale(), "dddd, d MMMM yyyy"),
                copy: d.toLocaleDateString(Qt.locale(), "dd.MM.yyyy"),
                hint: `${step[0]}  ·  ${Math.round((d - today) / day)} days from today`,
                icon: "event"
            };
        }
        const span = between(q, today);
        if (span)
            return span;
        const until = q.match(/^(?:до|until|till|days? (?:to|until))\s+(.+)$/);
        if (!until)
            return null;
        const s = until[1];
        let d = null;
        let m;
        if (/^(нг|new year|нового года|новый год)$/.test(s))
            d = new Date(today.getFullYear() + 1, 0, 1);
        else if ((m = s.match(/^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?$/)))
            d = new Date(m[3] ? (m[3].length === 2 ? 2000 + +m[3] : +m[3]) : today.getFullYear(), m[2] - 1, +m[1]);
        else if ((m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/)))
            d = new Date(+m[1], m[2] - 1, +m[3]);
        if (!d || isNaN(d))
            return null;
        // A date without a year that already passed means next year's
        if (!m?.[3] && m?.length === 4 && !s.includes("-") && d < today)
            d.setFullYear(d.getFullYear() + 1);
        const days = Math.round((d - today) / day);
        return {
            text: `${Math.abs(days)} ${Math.abs(days) === 1 ? "day" : "days"}${days < 0 ? " ago" : ""}`,
            copy: String(Math.abs(days)),
            hint: `${d.toLocaleDateString(Qt.locale(), "dddd, d MMMM yyyy")}  ·  ${(Math.abs(days) / 7).toFixed(1)} weeks`,
            icon: "event"
        };
    }

    // "dd.mm.yyyy", "dd/mm/yy" or "yyyy-mm-dd"
    function parseDate(s) {
        let m = s.match(/^(\d{1,2})[./](\d{1,2})[./](\d{2,4})$/);
        if (m)
            return new Date(m[3].length === 2 ? (+m[3] > 30 ? 1900 : 2000) + +m[3] : +m[3], m[2] - 1, +m[1]);
        m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})$/);
        return m ? new Date(+m[1], m[2] - 1, +m[3]) : null;
    }

    // "12.05.1998 - 03.08.2001", "от 12.05.1998 до 03.08.2001", "between ... and ...",
    // "возраст 12.05.1998" / "age 1998-05-12" counts up to today
    function between(q, today) {
        let a, b;
        const age = q.match(/^(?:возраст|age|сколько лет)\s+(\S+)$/);
        const pair = q.match(/^(?:от|from|between)?\s*(\S+)\s*(?:-|–|—|до|to|and|и)\s*(\S+)$/);
        if (age) {
            a = parseDate(age[1]);
            b = today;
        } else if (pair) {
            a = parseDate(pair[1]);
            b = parseDate(pair[2]);
        }
        if (!a || !b || isNaN(a) || isNaN(b))
            return null;
        if (a > b)
            [a, b] = [b, a];
        // Calendar difference: whole months that fit (a 31st steps to the month's last day), then the days left
        const shift = n => {
            const t = new Date(a.getFullYear(), a.getMonth() + n, 1);
            t.setDate(Math.min(a.getDate(), new Date(t.getFullYear(), t.getMonth() + 1, 0).getDate()));
            return t;
        };
        let months = (b.getFullYear() - a.getFullYear()) * 12 + b.getMonth() - a.getMonth();
        if (shift(months) > b)
            months--;
        const d = Math.round((b - shift(months)) / 86400000);
        const y = Math.floor(months / 12);
        const mo = months % 12;
        const parts = [[y, "year"], [mo, "month"], [d, "day"]].filter(([n]) => n).map(([n, w]) => `${n} ${w}${n === 1 ? "" : "s"}`);
        const days = Math.round((b - a) / 86400000);
        return {
            text: parts.join(" ") || "same day",
            copy: parts.join(" ") || "0",
            hint: `${format(days, 0)} days  ·  ${format(days / 7, 1)} weeks  ·  ${format(y + mo / 12 + d / 365.25, 2)} years`,
            icon: age ? "cake" : "date_range"
        };
    }

    // Recursive descent: + - * / ^ ! %, implicit multiplication "2pi", "2(3+1)"
    function evaluate(src) {
        const toks = src.replace(/×|·/g, "*").replace(/÷|:/g, "/").replace(/\*\*/g, "^")
            // "2,5" is a decimal comma; commas elsewhere separate arguments
            .replace(/(\d),(\d)/g, "$1.$2")
            .match(/\d*\.?\d+(?:e[+-]?\d+)?|[a-zπ]+\d*|[-+*/^()!%,;]|\S/g) ?? [];
        let i = 0;
        const peek = () => toks[i];
        const eat = t => toks[i] === t ? (i++, true) : false;

        function expr() {
            let v = term();
            for (;;) {
                if (eat("+")) v += term();
                else if (eat("-")) v -= term();
                else return v;
            }
        }
        function term() {
            let v = unary();
            for (;;) {
                if (eat("*")) v *= unary();
                else if (eat("/")) v /= unary();
                else if (eat("mod")) v %= unary();
                // Implicit multiplication before a number, name or bracket
                else if (peek() !== undefined && /^[\d.(a-zπ]/.test(peek()) && peek() !== "mod") v *= unary();
                else return v;
            }
        }
        function unary() {
            if (eat("-")) return -unary();
            if (eat("+")) return unary();
            return power();
        }
        function power() {
            const v = postfix();
            return eat("^") ? Math.pow(v, unary()) : v;
        }
        function postfix() {
            let v = primary();
            for (;;) {
                if (eat("!")) v = factorial(v);
                // "%" right before another operand is modulo, otherwise percent
                else if (peek() === "%" && toks[i + 1] !== undefined && /^[\d.(a-zπ]/.test(toks[i + 1])) { i++; v %= primary(); }
                else if (eat("%")) v /= 100;
                else return v;
            }
        }
        function primary() {
            const t = toks[i++];
            if (t === undefined) throw 0;
            if (/^[\d.]/.test(t)) return parseFloat(t);
            if (t === "(") {
                const v = expr();
                eat(")");
                return v;
            }
            if (t in consts) return consts[t];
            if (t in funcs) {
                if (!eat("(")) return funcs[t](unary());
                const args = [expr()];
                while (eat(",") || eat(";")) args.push(expr());
                eat(")");
                return funcs[t](...args);
            }
            throw 0;
        }

        try {
            const v = expr();
            return i === toks.length ? v : NaN;
        } catch (e) {
            return NaN;
        }
    }

    function factorial(n) {
        if (n < 0 || n !== Math.floor(n) || n > 170) return NaN;
        let r = 1;
        for (let k = 2; k <= n; k++) r *= k;
        return r;
    }

    // Enough decimals to keep 4 significant digits of small values, 2 for the rest
    function decimals(v) {
        const a = Math.abs(v);
        return a === 0 || a >= 1 ? 2 : Math.min(10, 3 - Math.floor(Math.log10(a)));
    }

    function money2(v) {
        return format(v, decimals(v));
    }

    // Up to `digits` decimals, trailing zeros dropped, float noise like 0.1+0.2 cleaned up
    function plain(v, digits) {
        if (Math.abs(v) >= 1e15 || v !== 0 && Math.abs(v) < 1e-9)
            return v.toPrecision(10).replace(/\.?0+e/, "e");
        return String(parseFloat(parseFloat(v.toPrecision(12)).toFixed(digits)));
    }

    // Thin-spaced thousands: 1 234 567.89
    function format(v, digits) {
        const s = plain(v, digits);
        if (s.includes("e"))
            return s;
        const [int, frac] = s.split(".");
        return int.replace(/\B(?=(\d{3})+(?!\d))/g, " ") + (frac ? "." + frac : "");
    }
}
