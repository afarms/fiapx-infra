// CloudFront viewer-request: retain body/query and reject ambiguous paths.
function handler(event) {
    var request = event.request;
    var uri = request.uri;
    var match = uri.match(/^\/api\/(identity|video)(\/.*)$/);
    if (!match || /[%\\;]/.test(uri) || /\/\//.test(uri) || /(^|\/)\.{1,2}(\/|$)/.test(uri)) {
        return {statusCode: 404, statusDescription: 'Not Found'};
    }
    var prefix = '/api/' + match[1];
    request.uri = match[2];
    // Never trust forwarding headers supplied by the viewer.
    delete request.headers['forwarded'];
    delete request.headers['x-forwarded-host'];
    delete request.headers['x-forwarded-port'];
    // X-Forwarded-Proto is not exposed by CloudFront; ALB adds HTTP downstream.
    // Spring gives the sanitized standard Forwarded header precedence.
    delete request.headers['x-forwarded-for'];
    delete request.headers['x-forwarded-prefix'];
    delete request.headers['x-fiapx-service'];
    request.headers['forwarded'] = {value: 'proto=https;host="' + request.headers.host.value + '"'};
    request.headers['x-forwarded-prefix'] = {value: prefix};
    return request;
}
