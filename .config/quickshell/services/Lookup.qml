pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Launcher answers that wait on the network or a process: "tr hello world", "tr de: привет", "time tokyo"
Singleton {
    id: root

    // Answer for `query`, null until it arrives or when the query isn't one of ours
    property string query: ""
    property var answer: null
    property var zones: []

    readonly property var cities: ({
        "москва": "Europe/Moscow", "мск": "Europe/Moscow", "питер": "Europe/Moscow", "санкт-петербург": "Europe/Moscow",
        "лондон": "Europe/London", "париж": "Europe/Paris", "берлин": "Europe/Berlin", "рим": "Europe/Rome",
        "мадрид": "Europe/Madrid", "амстердам": "Europe/Amsterdam", "прага": "Europe/Prague", "варшава": "Europe/Warsaw",
        "киев": "Europe/Kyiv", "kiev": "Europe/Kyiv", "минск": "Europe/Minsk", "стамбул": "Europe/Istanbul",
        "тбилиси": "Asia/Tbilisi", "ереван": "Asia/Yerevan", "баку": "Asia/Baku", "алматы": "Asia/Almaty",
        "астана": "Asia/Almaty", "ташкент": "Asia/Tashkent", "бишкек": "Asia/Bishkek", "дубай": "Asia/Dubai",
        "екатеринбург": "Asia/Yekaterinburg", "екб": "Asia/Yekaterinburg", "новосибирск": "Asia/Novosibirsk",
        "омск": "Asia/Omsk", "красноярск": "Asia/Krasnoyarsk", "иркутск": "Asia/Irkutsk", "владивосток": "Asia/Vladivostok",
        "калининград": "Europe/Kaliningrad", "самара": "Europe/Samara", "токио": "Asia/Tokyo", "сеул": "Asia/Seoul",
        "пекин": "Asia/Shanghai", "beijing": "Asia/Shanghai", "шанхай": "Asia/Shanghai", "гонконг": "Asia/Hong_Kong",
        "бангкок": "Asia/Bangkok", "сингапур": "Asia/Singapore", "дели": "Asia/Kolkata", "delhi": "Asia/Kolkata",
        "mumbai": "Asia/Kolkata", "мумбаи": "Asia/Kolkata", "нью-йорк": "America/New_York", "нью йорк": "America/New_York",
        "nyc": "America/New_York", "ny": "America/New_York", "лос-анджелес": "America/Los_Angeles", "la": "America/Los_Angeles",
        "los angeles": "America/Los_Angeles", "сан-франциско": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
        "sf": "America/Los_Angeles", "чикаго": "America/Chicago", "торонто": "America/Toronto", "мехико": "America/Mexico_City",
        "сидней": "Australia/Sydney", "мельбурн": "Australia/Melbourne", "utc": "UTC", "gmt": "UTC"
    })

    function request(q) {
        query = q;
        answer = null;
        debounce.restart();
    }

    function run() {
        const q = query.trim();
        const tr = q.match(/^(?:tr|ек|translate|перевод|переведи)\s+(?:([a-z]{2}):\s*)?(.+)$/i);
        if (tr)
            return translate(q, tr[2], tr[1]?.toLowerCase());
        const time = q.match(/^(?:time|время|сколько времени)\s+(?:in\s+|в\s+)?(.+)$/i);
        if (time)
            return clock(q, time[1].toLowerCase());
    }

    function get(url, done, fail) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let data = null;
            try {
                data = xhr.status === 200 ? JSON.parse(xhr.responseText) : null;
            } catch (e) {}
            data ? done(data) : fail?.();
        };
        xhr.open("GET", url);
        xhr.send();
    }

    // Cyrillic goes to English, anything else to Russian, unless "tr de: ..." names the target
    function translate(q, text, target) {
        const to = target ?? (/[а-яё]/i.test(text) ? "en" : "ru");
        const shown = (from, out) => {
            if (root.query === q)
                root.answer = { text: out, copy: out, hint: `${from || "auto"} → ${to}`, icon: "translate", wrap: true };
        };
        const enc = encodeURIComponent(text);
        get(`https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=${to}&q=${enc}`,
            data => shown(data[0]?.[1], Array.isArray(data[0]) ? data[0][0] : data[0]),
            // Google sometimes turns VPN addresses away; MyMemory needs the source language spelled out
            () => get(`https://api.mymemory.translated.net/get?q=${enc}&langpair=${to === "en" ? "ru" : "en"}|${to}`,
                data => shown(to === "en" ? "ru" : "en", data.responseData?.translatedText ?? "")));
    }

    function clock(q, place) {
        if (!zones.length) {
            pendingClock = [q, place];
            zoneList.running = true;
            return;
        }
        const key = place.replace(/\s+/g, "_");
        const zone = cities[place] ?? zones.find(z => z.toLowerCase().split("/").pop() === key)
            ?? zones.find(z => z.toLowerCase().split("/").pop().startsWith(key));
        if (!zone)
            return;
        offset.zone = zone;
        offset.q = q;
        offset.running = true;
    }

    property var pendingClock: null

    Timer {
        id: debounce
        interval: 250
        onTriggered: root.run()
    }

    Process {
        id: zoneList
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.zones = text.trim().split("\n");
                if (root.pendingClock)
                    root.clock(...root.pendingClock);
                root.pendingClock = null;
            }
        }
    }

    Process {
        id: offset
        property string zone
        property string q
        command: ["env", `TZ=${zone}`, "date", "+%z"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim().match(/^([+-])(\d\d)(\d\d)$/);
                if (!m || root.query !== offset.q)
                    return;
                const mins = (m[1] === "-" ? -1 : 1) * (+m[2] * 60 + +m[3]);
                const now = new Date();
                // A Date shifted so its local fields read as the zone's wall clock
                const there = new Date(now.getTime() + (mins + now.getTimezoneOffset()) * 60000);
                const diff = (mins + now.getTimezoneOffset()) / 60;
                const city = offset.zone.split("/").pop().replace(/_/g, " ");
                root.answer = {
                    text: there.toLocaleTimeString(Qt.locale(), "HH:mm"),
                    copy: there.toLocaleTimeString(Qt.locale(), "HH:mm"),
                    hint: `${city}  ·  ${there.toLocaleDateString(Qt.locale(), "ddd, d MMM")}  ·  UTC${m[1]}${+m[2]}${m[3] !== "00" ? ":" + m[3] : ""}  ·  `
                        + (diff === 0 ? "same as here" : `${diff > 0 ? "+" : ""}${diff} h from here`),
                    icon: "schedule"
                };
            }
        }
    }
}
