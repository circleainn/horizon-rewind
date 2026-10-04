// Horizon Rewind by circleainn. See LICENSE.txt for usage and redistribution terms.
/* global angular, bngApi */
'use strict';

angular.module('beamng.apps').directive('horizonRewind', ['$window', '$document', '$timeout', function ($window, $document, $timeout) {
  return {
    templateUrl: '/ui/modules/apps/HorizonRewind/app.html',
    restrict: 'E',
    replace: true,
    scope: true,
    link: function (scope, element) {
      var document = $document[0];
      var button = element[0].querySelector('.hr-hold');
      var held = false;
      var heldKey = null;
      var pointerId = null;
      var connected = false;
      var destroyed = false;
      var removers = [];

      scope.hr = {
        enabled: false,
        phase: 'disabled',
        availableSeconds: 0,
        rewindSeconds: 0,
        maxSeconds: 20,
        speed: 2,
        message: 'Loading rewind…',
        damageMode: 'experimental'
      };
      scope.hrHeld = false;
      scope.hrSpeeds = [0.25, 0.5, 1, 2, 4, 8];

      function send(command) {
        bngApi.engineLua("if not extensions.horizonRewind then extensions.load('horizonRewind') end if extensions.horizonRewind then extensions.horizonRewind." + command + ' end');
      }

      function finite(value, fallback) {
        return typeof value === 'number' && isFinite(value) ? value : fallback;
      }

      function clearHold() {
        held = false;
        heldKey = null;
        scope.hrHeld = false;
        var previousPointer = pointerId;
        pointerId = null;
        if (previousPointer !== null && button.hasPointerCapture && button.hasPointerCapture(previousPointer)) {
          button.releasePointerCapture(previousPointer);
        }
      }

      function finish(cancel) {
        if (!held) return;
        clearHold();
        send(cancel ? 'cancelRewind()' : 'endRewind()');
        if (!destroyed) scope.$evalAsync();
      }

      scope.hrCanRewind = function () {
        return scope.hr.enabled && scope.hr.phase === 'recording' && scope.hr.availableSeconds > 0;
      };

      function begin() {
        if (held || !scope.hrCanRewind()) return false;
        held = true;
        scope.hrHeld = true;
        send('beginRewind()');
        scope.$evalAsync();
        return true;
      }

      scope.hrCancel = function () {
        if (held) finish(true);
        else send('cancelRewind()');
      };

      scope.hrSetSpeed = function (speed) {
        if (scope.hrSpeeds.indexOf(speed) !== -1) send('setSpeed(' + speed + ')');
      };

      scope.hrStatus = function () {
        return {
          disabled: 'Standby',
          recording: scope.hr.availableSeconds > 0 ? 'Ready' : 'Building history',
          rewinding: 'Rewinding',
          restoring: 'Restoring car',
          error: 'Needs attention'
        }[scope.hr.phase] || 'Standby';
      };

      scope.hrPosition = function () {
        if (scope.hr.availableSeconds <= 0) return 100;
        return Math.max(0, Math.min(100, 100 * (1 - scope.hr.rewindSeconds / scope.hr.availableSeconds)));
      };

      scope.hrBuffer = function () {
        return Math.max(0, Math.min(100, 100 * scope.hr.availableSeconds / scope.hr.maxSeconds));
      };

      scope.$on('HorizonRewindState', function (_, state) {
        if (!state || destroyed) return;
        connected = true;
        scope.$evalAsync(function () {
          scope.hr.enabled = !!state.enabled;
          scope.hr.phase = state.phase || 'disabled';
          scope.hr.maxSeconds = Math.max(0.1, finite(state.maxSeconds, 20));
          scope.hr.availableSeconds = Math.max(0, finite(state.availableSeconds, 0));
          scope.hr.rewindSeconds = Math.max(0, finite(state.rewindSeconds, 0));
          scope.hr.speed = finite(state.speed, 2);
          scope.hr.message = typeof state.message === 'string' ? state.message : '';
          scope.hr.damageMode = state.damageMode || 'experimental';
          if (held && ['disabled', 'restoring', 'error'].indexOf(scope.hr.phase) !== -1) clearHold();
        });
      });

      function listen(target, event, listener) {
        target.addEventListener(event, listener, false);
        removers.push(function () { target.removeEventListener(event, listener, false); });
      }

      if ($window.PointerEvent) {
        listen(button, 'pointerdown', function (event) {
          if (event.button !== 0 || !event.isPrimary) return;
          event.preventDefault();
          if (!begin()) return;
          pointerId = event.pointerId;
          button.focus();
          if (button.setPointerCapture) button.setPointerCapture(pointerId);
        });
        listen(document, 'pointerup', function (event) {
          if (pointerId === event.pointerId) finish(false);
        });
        listen(document, 'pointercancel', function (event) {
          if (pointerId === event.pointerId) finish(true);
        });
        listen(button, 'lostpointercapture', function (event) {
          if (pointerId === event.pointerId) finish(true);
        });
      } else {
        listen(button, 'mousedown', function (event) {
          if (event.button !== 0) return;
          event.preventDefault();
          button.focus();
          begin();
        });
        listen(document, 'mouseup', function (event) {
          if (event.button === 0 && heldKey === null) finish(false);
        });
      }

      listen(button, 'keydown', function (event) {
        if (event.key !== ' ' && event.key !== 'Enter') return;
        event.preventDefault();
        if (!event.repeat && begin()) heldKey = event.key;
      });
      listen(document, 'keyup', function (event) {
        if (heldKey === event.key) {
          event.preventDefault();
          finish(false);
        }
      });
      listen(document, 'keydown', function (event) {
        if (event.key === 'Escape' && held) {
          event.preventDefault();
          finish(true);
        }
      });
      listen(button, 'blur', function () {
        if (heldKey !== null) finish(true);
      });
      listen(button, 'contextmenu', function (event) { event.preventDefault(); });
      listen($window, 'blur', function () { finish(true); });
      listen(document, 'visibilitychange', function () {
        if (document.hidden) finish(true);
      });

      var connectionTimeout = $timeout(function () {
        if (!connected) {
          scope.hr.phase = 'error';
          scope.hr.message = 'No response from the mod. Check installation, then reload the UI.';
        }
      }, 5000);

      scope.$on('$destroy', function () {
        destroyed = true;
        finish(true);
        $timeout.cancel(connectionTimeout);
        removers.forEach(function (remove) { remove(); });
      });

      send('requestState()');
    }
  };
}]);
