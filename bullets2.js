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
var traceAttacks = [];

// POST route// --- In-memory trace storage ---
var traceAttacks = [];

// POST route: accepts single object or array of trace objects
app.post("/traceattacks", (req, res) => {
  const body = req.body;
  if (!body) return res.status(400).json({ error: "Empty request body" });

  const items = Array.isArray(body) ? body : [body];
  const storedEntries = [];

  for (const item of items) {
    if (!item) continue;

    const { attacker, victim, damage, hitpos } = item;

    // Basic required-field check
    if (hitpos == null) {
      continue;
    }

    // Normalize hitpos into [x, y, z] numbers
    let hp = hitpos;

    // 1) If it's a space-separated string "100 200 300"
    if (typeof hp === "string") {
      const parts = hp.trim().split(/\s+/).map(Number);
      if (parts.length !== 3 || parts.some(isNaN)) continue;
      hp = parts;
    }
    // 2) If it's already an array [x,y,z]
    else if (Array.isArray(hp)) {
      if (hp.length !== 3 || hp.some(v => typeof v !== "number")) continue;
    }
    // 3) If it's an object like { x:..., y:..., z:... } or numeric keys
    else if (typeof hp === "object" && hp !== null) {
      if (hp.x != null && hp.y != null && hp.z != null) {
        const x = Number(hp.x), y = Number(hp.y), z = Number(hp.z);
        if ([x, y, z].some(isNaN)) continue;
        hp = [x, y, z];
      } else if (hp[0] != null && hp[1] != null && hp[2] != null) {
        const x = Number(hp[0]), y = Number(hp[1]), z = Number(hp[2]);
        if ([x, y, z].some(isNaN)) continue;
        hp = [x, y, z];
      } else {
        continue;
      }
    } else {
      continue; // unrecognized hitpos format
    }

    // Build stored trace object (preserve optional fields)
    const traceEntry = {
        hitpos: hp[0] + " " + hp[1] + " " + hp[2],
        damage: damage
    };

    traceAttacks.push(traceEntry);
    storedEntries.push(traceEntry);

    // Keep memory sane
    if (traceAttacks.length > 500) traceAttacks.shift();

    // Broadcast to connected clients
    if (typeof io !== "undefined") {
      io.emit("trace", traceEntry);
    }
  }

  if (storedEntries.length === 0) {
    return res.status(400).json({ error: "No valid trace entries in request" });
  }

  return res.status(200).json({ success: true, stored: storedEntries.length });
});



// --- GET /traceattacks ---
// Return all trace attacks or filter by attacker/victim
app.get("/traceattacks", (req, res) => {
    let results = traceAttacks;
    res.status(200).json(results);
    traceAttacks = [];  
});


io.on("connection", socket => {
    console.log("Client connected!");
});
// --- CHAT SYSTEM ---
// In-memory chat message storage
let chatMessages = [];

// POST /chat
// Example body: { name: "Player1", text: "Hello world" }
app.post("/chat", (req, res) => {
    const body = req.body;
    if (!body || typeof body.name !== "string" || typeof body.text !== "string") {
        return res.status(400).json({ error: "Invalid chat message format" });
    }

    const name = body.name.trim();
    const text = body.text.trim();
    if (!name || !text) {
        return res.status(400).json({ error: "Missing name or text" });
    }

    // Build message object
    const message = {
        name,
        text,
        time: Date.now()
    };

    chatMessages.push(message);

    // Limit to last 100 messages
    if (chatMessages.length > 100) chatMessages.shift();

    // Broadcast to all connected Socket.IO clients
    io.emit("chat", message);

    res.status(200).json({ success: true });
});

// GET /chat
// Returns all stored chat messages (and clears them after)
app.get("/chat", (req, res) => {
    res.json(chatMessages);
    chatMessages = []; // Clear after sending (like your traceAttacks)
});

app.use(express.static('./html'));

server.listen(7001, () => console.log("Server running on http://localhost:7001"));
