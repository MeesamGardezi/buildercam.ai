import { Server } from 'socket.io';

import { saveProjectTranscript } from './services/firestore.service.js';

let io = null;

export function initSocketIO(httpServer) {
  io = new Server(httpServer, {
    cors: { origin: true },
    pingTimeout: 60000,
    pingInterval: 25000,
  });

  io.on('connection', (socket) => {
    console.log(`[Socket.IO] Client connected: ${socket.id}`);

    socket.on('join_project', ({ projectId }) => {
      if (!projectId) {
        return;
      }
      socket.join(`project:${projectId}`);
      console.log(`[Socket.IO] ${socket.id} joined project:${projectId}`);
    });

    socket.on('transcript_update', async (data) => {
      const { projectId, transcriptId, rawTranscript, durationSeconds, createdBy } = data || {};
      if (!projectId || !String(rawTranscript || '').trim()) {
        return;
      }

      try {
        const { transcript } = await saveProjectTranscript(projectId, {
          id: transcriptId || undefined,
          rawTranscript: String(rawTranscript).trim(),
          durationSeconds: Number(durationSeconds || 0),
          createdBy: createdBy || 'socket-client',
          status: 'in_progress',
        });

        socket.to(`project:${projectId}`).emit('transcript_synced', {
          transcript,
        });

        socket.emit('transcript_ack', {
          id: transcript.id,
          savedAt: transcript.updatedAt,
        });
      } catch (error) {
        socket.emit('transcript_error', { message: error.message });
        console.error('[Socket.IO] transcript_update error:', error.message);
      }
    });

    socket.on('transcript_final', async (data) => {
      const { projectId, transcriptId, rawTranscript, durationSeconds, createdBy } = data || {};
      if (!projectId || !String(rawTranscript || '').trim()) {
        return;
      }

      try {
        const { transcript, created } = await saveProjectTranscript(projectId, {
          id: transcriptId || undefined,
          rawTranscript: String(rawTranscript).trim(),
          durationSeconds: Number(durationSeconds || 0),
          createdBy: createdBy || 'socket-client',
          status: 'completed',
        });

        io.to(`project:${projectId}`).emit('transcript_finalized', {
          transcript,
          created,
        });

        socket.emit('transcript_ack', {
          id: transcript.id,
          savedAt: transcript.updatedAt,
        });
        console.log(
          `[Socket.IO] Saved final transcript ${transcript.id} for project ${projectId}`,
        );
      } catch (error) {
        socket.emit('transcript_error', { message: error.message });
        console.error('[Socket.IO] transcript_final error:', error.message);
      }
    });

    socket.on('disconnect', (reason) => {
      console.log(`[Socket.IO] Client disconnected: ${socket.id} (${reason})`);
    });
  });

  return io;
}

export function getIO() {
  return io;
}
