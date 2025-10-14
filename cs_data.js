import express from "express";
import http from "http";
import { Server } from "socket.io";
import bodyParser from "body-parser";

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: "*" }
});

app.use(bodyParser.json());

let latestUpdates = [];       // from SourceMod
let latestUpdatesCS = [];       // from SourceMod
let latestUpdatesGMod = [];   // from GMod players
let latestUpdatesProp = [];   // from GMod props
let latestSounds = [];        // from sound POSTs
let latestSounds2 = [];        // from sound POSTs

// HTTP POST endpoint for player updates
app.post("/update", (req, res) => {
    if (req.body && Array.isArray(req.body.players)) {
        latestUpdates = req.body;
        //console.log(`[SourceMod] Received ${latestUpdates.players.length} players`);
    }
    res.sendStatus(200);
});

app.post("/update_css", (req, res) => {
    if (req.body && Array.isArray(req.body.players)) {
        latestUpdatesCS = req.body;
        //console.log(`[SourceMod] Received ${latestUpdates.players.length} players`);
    }
    res.sendStatus(200);
});


// HTTP GET endpoint for browser polling (player updates)
app.get("/update", (req, res) => {
    res.json(latestUpdates);   // return all stored updates
});

// HTTP GET endpoint for browser polling (player updates)
app.get("/update_css", (req, res) => {
    res.json(latestUpdatesCS);   // return all stored updates
});

app.post("/update_gmod", (req, res) => {
    if (req.body && req.body.data) {
        latestUpdatesGMod = req.body.data;  // store the data
    }
    res.sendStatus(200);
});

// HTTP GET endpoint for browser polling (player updates)
app.get("/update_gmod", (req, res) => {
    res.json(latestUpdatesGMod);   // return all stored updates
});

app.post("/update_props", (req, res) => {
    if (req.body && req.body) {
        latestUpdatesProp = req.body;  // store the data
    }
    res.sendStatus(200);
});

// HTTP GET endpoint for browser polling (player updates)
app.get("/update_props", (req, res) => {
    res.json(latestUpdatesProp);   // return all stored updates 
});

// --- SOUND EVENTS ---
// POST route: GMod sends when a sound plays
app.post("/sound", (req, res) => {
    if (req.body && req.body.sound) {
        // Example: { sound: "vo/npc/male01/hi01.wav", pos: { x: 0, y: 0, z: 0 }, volume: 1.0 }
        latestSounds.push({
            sound: req.body.sound,
            pos: req.body.pos || null,
            volume: req.body.volume || 1.0,
            time: Date.now()
        });

        // Optional: only keep last 100 sounds
        if (latestSounds.length > 100) latestSounds.shift();

        io.emit("sound", req.body); // optionally broadcast to web clients
    }
    res.sendStatus(200);
});

// GET route: returns the latest list of sound events
app.get("/sound", (req, res) => {
    res.json(latestSounds);
    latestSounds = [];
});

// --- In-memory trace storage ---
const traceAttacks = [];

// POST route
app.post("/traceattacks", (req, res) => {
    if (!req.body) {
        return res.status(400).json({ error: "Empty request body" });
    }

    const { attacker, victim, damage, hitpos } = req.body;

    if (!attacker || !victim || damage == null || !hitpos) {
        return res.status(400).json({ error: "Missing required fields" });
    }

    // store trace...
    res.status(201).json({ success: true });
});

// --- GET /traceattacks ---
// Return all trace attacks or filter by attacker/victim
app.get("/traceattacks", (req, res) => {
  const { attacker, victim } = req.query;

  let results = traceAttacks;
  if (attacker)
    results = results.filter(t => t.attacker === attacker);
  if (victim)
    results = results.filter(t => t.victim === victim);

  res.json(results);
});


io.on("connection", socket => {
    console.log("Client connected!");
});

app.use(express.static('./html'));

server.listen(2635, () => console.log("Server running on http://localhost:2635"));
