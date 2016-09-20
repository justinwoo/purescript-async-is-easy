exports.foreignCalculateLength = function(array) {
  return function (callback) {
    return callback(array.length);
  };
};