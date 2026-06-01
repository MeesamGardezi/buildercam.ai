'use strict';
// LiteSpeed's lsnode.js uses require(), which cannot directly load ES Modules.
// This CommonJS wrapper bootstraps the ESM server via dynamic import().
(async () => {
  await import('./src/server.js');
})();
