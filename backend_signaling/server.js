'use strict';

const http = require('http');
const express = require('express');
const cors = require('cors');
const { Server } = require('socket.io');

const PORT = Number(process.env.PORT || 3000);

const app = express();
app.use(cors({ origin: '*', methods: ['GET', 'POST', 'OPTIONS'] }));
app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'linguacall-signaling' });
});

const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'], credentials: false },
  transports: ['websocket', 'polling'],
});

/** @type {Map<string, string>} uid -> socket.id */
const uidToSocket = new Map();

function socketUid(socket) {
  return socket.data && socket.data.uid ? String(socket.data.uid) : '';
}

io.on('connection', (socket) => {
  socket.on('register-user', (payload) => {
    const uid = payload && payload.uid != null ? String(payload.uid) : '';
    if (!uid) return;
    socket.data.uid = uid;
    uidToSocket.set(uid, socket.id);
    socket.join(`uid:${uid}`);
    console.log(`[register-user] ${uid} -> ${socket.id}`);
  });

  socket.on('call-user', (payload) => {
    const callerUid = socketUid(socket);
    const targetUid =
      payload && payload.targetUid != null ? String(payload.targetUid) : '';
    const type = payload && payload.type != null ? String(payload.type) : 'voice';
    if (!callerUid || !targetUid) return;

    const targetSocketId = uidToSocket.get(targetUid);
    if (!targetSocketId) {
      socket.emit('call-failed', { reason: 'offline', targetUid });
      return;
    }

    const callId = `${callerUid}_${targetUid}_${Date.now()}`;
    io.to(targetSocketId).emit('incoming-call', {
      callerUid,
      targetUid,
      type,
      callId,
    });
    console.log(`[call-user] ${callerUid} -> ${targetUid} (${type})`);
  });

  socket.on('accept-call', (payload) => {
    const accepterUid = socketUid(socket);
    const targetUid =
      payload && payload.targetUid != null ? String(payload.targetUid) : '';
    if (!accepterUid || !targetUid) return;

    const callerSocketId = uidToSocket.get(targetUid);
    if (!callerSocketId) return;

    io.to(callerSocketId).emit('call-accepted', {
      accepterUid,
      callerUid: targetUid,
    });
    console.log(`[accept-call] ${accepterUid} accepted from ${targetUid}`);
  });

  socket.on('reject-call', (payload) => {
    const rejecterUid = socketUid(socket);
    const targetUid =
      payload && payload.targetUid != null ? String(payload.targetUid) : '';
    if (!rejecterUid || !targetUid) return;

    const callerSocketId = uidToSocket.get(targetUid);
    if (!callerSocketId) return;

    io.to(callerSocketId).emit('call-rejected', {
      rejecterUid,
      callerUid: targetUid,
    });
    console.log(`[reject-call] ${rejecterUid} rejected ${targetUid}`);
  });

  socket.on('offer', (payload) => {
    const from = socketUid(socket);
    const to = payload && payload.to != null ? String(payload.to) : '';
    const sdp = payload && payload.sdp != null ? String(payload.sdp) : '';
    if (!from || !to || !sdp) return;

    const targetSocketId = uidToSocket.get(to);
    if (!targetSocketId) return;

    io.to(targetSocketId).emit('offer', { from, sdp });
  });

  socket.on('answer', (payload) => {
    const from = socketUid(socket);
    const to = payload && payload.to != null ? String(payload.to) : '';
    const sdp = payload && payload.sdp != null ? String(payload.sdp) : '';
    if (!from || !to || !sdp) return;

    const targetSocketId = uidToSocket.get(to);
    if (!targetSocketId) return;

    io.to(targetSocketId).emit('answer', { from, sdp });
  });

  socket.on('ice-candidate', (payload) => {
    const from = socketUid(socket);
    const to = payload && payload.to != null ? String(payload.to) : '';
    if (!from || !to) return;

    const targetSocketId = uidToSocket.get(to);
    if (!targetSocketId) return;

    io.to(targetSocketId).emit('ice-candidate', {
      from,
      candidate: payload.candidate,
      sdpMid: payload.sdpMid,
      sdpMLineIndex: payload.sdpMLineIndex,
    });
  });

  socket.on('disconnect', () => {
    const uid = socketUid(socket);
    if (uid && uidToSocket.get(uid) === socket.id) {
      uidToSocket.delete(uid);
      console.log(`[disconnect] ${uid}`);
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`LinguaCall signaling on 0.0.0.0:${PORT} (PORT from env)`);
});
