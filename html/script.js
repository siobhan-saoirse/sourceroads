async function fetchUpdates() {
    const response = await fetch("http://localhost:7001/traceattacks");
    if (!response.ok) return;
    const data = await response.json();
    console.log(data);
}

setInterval(fetchUpdates, 100); // every 0.1 sec