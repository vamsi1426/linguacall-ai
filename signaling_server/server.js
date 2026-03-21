const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');

const app = express();
app.use(cors());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*', // Allow Flutter web/mobile requests
    methods: ['GET', 'POST'],
  },
});

// Store connected users: uid -> socket.id
const users = new Map();

io.on('connection', (socket) => {
  console.log(`User connected: ${socket.id}`);

  // Register user with their uid (from Firebase)
  socket.on('register-user', ({ uid }) => {
    if (uid) {
      users.set(uid, socket.id);
      socket.uid = uid;
      console.log(`Registered user ${uid} with socket ${socket.id}`);
    }
  });

  // Call user
  socket.on('call-user', ({ targetUid, callerUid, type }) => {
    const targetSocket = users.get(targetUid);
    if (targetSocket) {
      io.to(targetSocket).emit('incoming-call', {
        callerUid,
        type, // 'audio' or 'video'
        socketId: socket.id
      });
      console.log(`${callerUid} calling ${targetUid}`);
    } else {
      socket.emit('call-failed', { reason: 'user_offline' });
    }
  });

  // Accept call
  socket.on('accept-call', ({ targetUid }) => {
    const targetSocket = users.get(targetUid);
    if (targetSocket) {
      io.to(targetSocket).emit('call-accepted', { receiverUid: socket.uid });
    }
  });

  // Reject call
  socket.on('reject-call', ({ targetUid }) => {
    const targetSocket = users.get(targetUid);
    if (targetSocket) {
      io.to(targetSocket).emit('call-rejected', { receiverUid: socket.uid });
    }
  });

  // End call
  socket.on('end-call', ({ targetUid }) => {
    const targetSocket = users.get(targetUid);
    if (targetSocket) {
      io.to(targetSocket).emit('call-ended', { uid: socket.uid });
    }
  });

  // WebRTC Signaling: Offer
  socket.on('offer', ({ targetUid, sdp }) => {
    const targetSocket = users.get(targetUid);
    if (targetSocket) {
      io.to(targetSocket).emit('offer', { senderUid: socket.uid, sdp });
    }
  });

  // WebRTC Signaling: Answer
  socket.on('answer', ({ targetUid, sdp }) => {
    const targetSocket = users.get(targetUid);
    if (targetSocket) {
      io.to(targetSocket).emit('answer', { senderUid: socket.uid, sdp });
    }
  });

  // WebRTC Signaling: ICE Candidate
  socket.on('ice-candidate', ({ targetUid, candidate }) => {
    const targetSocket = users.get(targetUid);
    if (targetSocket) {
      io.to(targetSocket).emit('ice-candidate', { senderUid: socket.uid, candidate });
    }
  });

  // Disconnect
  socket.on('disconnect', () => {
    if (socket.uid) {
      users.delete(socket.uid);
      console.log(`User ${socket.uid} disconnected`);
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`Signaling server running on port ${PORT}`);
});
