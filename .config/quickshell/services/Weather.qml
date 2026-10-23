pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Open-Meteo forecast for a city typed in the calendar panel; until one is set,
// the location comes from the IP (which a VPN can move to another country)
Singleton {
    id: root

    property string city: ""
    property real lat: NaN
    property real lon: NaN
    property bool loading: false
    property bool failed: false
    property real fetchedAt: 0

    property var current: null
    property var days: []

    function setCity(name) {
        name = name.trim();
        if (name === city && !isNaN(lat))
            return;
        city = name;
        lat = lon = NaN;
        saved.setText(name);
        locate();
    }

    function refresh() {
        if (Date.now() - fetchedAt > 15 * 60000)
            isNaN(lat) ? locate() : fetchForecast();
    }

    function get(url, done) {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let data = null;
            try {
                data = xhr.status === 200 ? JSON.parse(xhr.responseText) : null;
            } catch (e) {}
            if (data)
                done(data);
            else {
                root.loading = false;
                root.failed = true;
            }
        };
        xhr.open("GET", url);
        xhr.send();
    }

    function locate() {
        loading = true;
        failed = false;
        if (city) {
            get(`https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&name=${encodeURIComponent(city)}`, data => {
                const hit = data.results?.[0];
                if (!hit) {
                    loading = false;
                    failed = true;
                    return;
                }
                place = hit.name;
                lat = hit.latitude;
                lon = hit.longitude;
                fetchForecast();
            });
        } else {
            get("http://ip-api.com/json", data => {
                place = data.city ?? "";
                lat = data.lat;
                lon = data.lon;
                fetchForecast();
            });
        }
    }

    property string place: ""

    function fetchForecast() {
        loading = true;
        get(`https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&timezone=auto&forecast_days=6`
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min", data => {
            const c = data.current;
            current = {
                temp: Math.round(c.temperature_2m),
                feels: Math.round(c.apparent_temperature),
                humidity: c.relative_humidity_2m,
                wind: Math.round(c.wind_speed_10m),
                code: c.weather_code,
                day: c.is_day === 1
            };
            const d = data.daily;
            days = d.time.map((t, i) => ({
                day: t,
                date: new Date(t + "T12:00"),
                code: d.weather_code[i],
                max: Math.round(d.temperature_2m_max[i]),
                min: Math.round(d.temperature_2m_min[i])
            }));
            fetchedAt = Date.now();
            loading = false;
            failed = false;
            last.setText(JSON.stringify({ city, place, lat, lon, current, days, fetchedAt }));
        });
    }

    // WMO weather codes
    function icon(code, day) {
        if (code === 0) return day === false ? "clear_night" : "sunny";
        if (code <= 2) return day === false ? "partly_cloudy_night" : "partly_cloudy_day";
        if (code === 3) return "cloud";
        if (code <= 48) return "foggy";
        if (code <= 57) return "rainy_light";
        if (code <= 67) return "rainy";
        if (code <= 77) return "weather_snowy";
        if (code <= 82) return "rainy_heavy";
        if (code <= 86) return "snowing_heavy";
        return "thunderstorm";
    }

    function describe(code) {
        if (code === 0) return "Clear";
        if (code <= 2) return "Partly cloudy";
        if (code === 3) return "Overcast";
        if (code <= 48) return "Fog";
        if (code <= 57) return "Drizzle";
        if (code <= 67) return "Rain";
        if (code <= 77) return "Snow";
        if (code <= 82) return "Showers";
        if (code <= 86) return "Snow showers";
        return "Thunderstorm";
    }

    Timer {
        interval: 30 * 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    FileView {
        id: saved
        path: Quickshell.statePath("weather-city")
        blockLoading: true
        printErrors: false
    }

    // Last forecast, shown at once on start while a fresh one loads
    FileView {
        id: last
        path: Quickshell.cachePath("weather.json")
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        city = saved.text().trim();
        let c = null;
        try {
            c = JSON.parse(last.text());
        } catch (e) {}
        if (c?.city !== city || !c.days)
            return locate();
        place = c.place;
        lat = c.lat;
        lon = c.lon;
        current = c.current;
        days = c.days.map(d => Object.assign({}, d, { date: new Date(d.day + "T12:00") }));
        fetchedAt = c.fetchedAt;
        refresh();
    }
}
