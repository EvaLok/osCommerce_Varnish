# This is an oscommerce VCL configuration file for varnish.  See the vcl(7)
# man page for details on VCL syntax and semantics.
# 
# This VCL is (c) John McLear 2013
# 
# Default backend definition.  Set this to your OSCommerce Apache / Nginx instance
# 

# Allow Logging
import std;

# Define a backend (in this case Apache is listening on 8080)
backend default {
  .host = "127.0.0.1";
  .port = "8080";
}

# End points for purge requests, OS Commerce can't do purge requests yet but site admins can directly from CLI or HTTP requests
acl purge {
  "127.0.0.1";
}

sub vcl_fetch{
  # Compress Text
  if (beresp.http.content-type ~ "text") {
    set beresp.do_gzip = true;
  }

  # When fetching images we can set a long caching marker that we can access later
  if (req.request == "GET" && req.url ~ "\.(js|jpg|jpeg|gif|ico|css|png)$") {
    set beresp.http.magicmarker = "1";
    unset req.http.cookie;
  }

  # When fetching thumbnails set caching magic marker
  if (req.request == "GET" && req.url ~ "product_thumb") {
    std.log("Thumbnail REQUEST!");
    unset req.http.cookie;
    set beresp.http.magicmarker = "1";
  }

  # Don't cache error pages
  if (beresp.status == 404 || beresp.status == 503 || beresp.status >= 500){
    set beresp.ttl = 0s;
  }
 
  # Some debug code for why objects are/aren't cachable
  # Varnish determined the object was not cacheable
  if (!beresp.ttl > 0s) {
    set beresp.http.X-Cacheable = "NO:Not Cacheable";
 
    # You don't wish to cache content for logged in users
    } elsif (req.http.Cookie ~ "(UserID|_session)") {  // TODO change to OSCommerce
      set beresp.http.X-Cacheable = "NO:Got Session";
      std.log("It appears a session is in process so we have returned pass");
      return(deliver);
 
    # You are respecting the Cache-Control=private header from the backend
    } elsif (beresp.http.Cache-Control ~ "private") {
      set beresp.http.X-Cacheable = "NO:Cache-Control=private";
      std.log("It appears this is private so we have returned pass");
      return(deliver);
 
    # You are extending the lifetime of the object artificially
    } elsif (beresp.ttl < 1s) {
      set beresp.ttl   = 5s;
      set beresp.grace = 5s;
      set beresp.http.X-Cacheable = "YES:FORCED";
      # Varnish determined the object was cacheable
  } else {
    # The Request can be cached
    set beresp.http.X-Cacheable = "YES";
  }
}

sub vcl_recv {
  # Set the client IP in the X-Forwarded-For header, we use mod_rpaf to rewrite this to the corret header
  set req.http.X-Forwarded-For = client.ip;

  # Set the backend to Apache
  set req.backend = default; 

  # Purge requests for purge
  if (req.request == "PURGE") {
    if (!client.ip ~ purge) {
      error 405 "Not allowed.";
    }
    ban("req.url ~ "+req.url);
    ban("req.url = " + req.url + " && req.http.host = " + req.http.host);
    error 200 "Purged.";
  }

  # Cache static objects such as images
  if (req.request == "GET" && req.url ~ "\.(jpg|jpeg|gif|ico|css|js|png)$") {
    unset req.http.cookie;
    # std.log("request is for a file such as jpg jpeg etc so dropping cookie");
    return(lookup);
  }
  # Cache product thumbs
  if (req.request == "GET" && req.url ~ "product_thumb"){
    # std.log("Thumbnails dont need to have a cookie, destroy it.");
    unset req.http.cookie;
    return(lookup);
  }
}

sub vcl_deliver {
  # If the magic marker is set allow the client to long cache the object and not re-request it for a long time (2016)
  if (resp.http.magicmarker) {
    std.log("Magicmarker set so setting our own client side caching");
    unset resp.http.magicmarker;
    set resp.http.Cache-Control = "max-age=648000";
    set resp.http.Expires = "Thu, 01 May 2016 00:10:22 GMT";
    set resp.http.Last-Modified = "Mon, 25 Apr 2011 01:00:00 GMT";
    set resp.http.Age = "647";
  }
}
 
