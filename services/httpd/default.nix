{ config, pkgs, ... }:
let
  common = import ../../common/variables.nix;
  vhosts = import ./vhosts.nix { inherit config; };
  adminAddr = "webmaster@${common.tld}";

  # Define a base vhost for all TLDs. This will serve only ACME on port 80
  # Everything else is promoted to HTTPS
  acmeVhost = domain: {
    inherit adminAddr;
    hostName = domain;
    serverAliases = [ "*.${domain}" ];
    listen = [{ port = 80; }];
    servedDirs = [{
      urlPath = "/.well-known/acme-challenge";
      dir = "${common.webrootDir}/.well-known/acme-challenge";
    }];

    extraConfig = ''
      RewriteEngine On
      RewriteCond %{HTTPS} off
      RewriteCond %{REQUEST_URI} !^/\.well-known/.*$ [NC]
      RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI} [R=301]
    '';
  };

  redbrickVhost = let
    documentRoot = "${common.webtreeDir}/redbrick/htdocs";
  in {
    inherit adminAddr documentRoot;
    hostName = common.tld;
    serverAliases = [ "www.${common.tld}" ];
    listen = [{ port = 443; }];
    enableSSL = true;
    extraConfig = ''
      Alias /cgi-bin/ "${common.webtreeDir}/redbrick/extras/cgi-bin/"
      Alias /robots.txt "${common.webtreeDir}/redbrick/extras/robots.txt"

      ErrorDocument 400 /404
      ErrorDocument 404 /404
      ErrorDocument 500 /404
      ErrorDocument 502 /404
      ErrorDocument 503 /404
      ErrorDocument 504 /404

      # Redirect rb.dcu.ie/~user => user.rb.dcu.ie
      RedirectMatch 301 "^/~(.*)(/(.*))?$" "https://$1.${common.tld}/$2"

      # Redirect /cmt to cmtwiki.rb
      RedirectMatch 301 "^/cmt/wiki(/(.*))?$" "https://cmtwiki.${common.tld}/$1"

      <Directory ${documentRoot}>
        RewriteEngine on
        RewriteBase /
        RewriteRule ^index\.html$ - [L]
        RewriteCond %{REQUEST_FILENAME} !-f
        RewriteCond %{REQUEST_FILENAME} !-d
        RewriteCond %{REQUEST_FILENAME} !-l
        RewriteRule . /index.html [L]
      </Directory>
    '';
  };
in {
  imports = [
    ./php-fpm.nix
    ./mediawiki.nix
  ];

  # Enable suexec support
  nixpkgs.overlays = [
    (self: super: {
      apacheHttpd = super.apacheHttpd.overrideAttrs (oldAttrs: {
        patches = [ ./httpd-skip-setuid.patch ];
        configureFlags = [
          "--enable-suexec"
          "--with-suexec-bin=/run/wrappers/bin/suexec"
        ] ++ oldAttrs.configureFlags;
      });
    })
  ];

  # NixOS has strict control over setuid
  security.wrappers.suexec = {
    source = "${pkgs.apacheHttpd.out}/bin/suexec";
    capabilities = "cap_setuid,cap_setgid+pe";
    permissions = "4750";
    owner = "root";
    group = "wwwrun";
  };

  services.httpd = {
    inherit adminAddr;
    enable = true;
    extraModules = [ "suexec" "proxy" "proxy_fcgi" "ldap" "authnz_ldap" ];
    multiProcessingModule = "event";
    maxClients = 250;
    sslServerKey = "${common.certsDir}/${common.tld}/key.pem";
    sslServerCert = "${common.certsDir}/${common.tld}/fullchain.pem";

    extraConfig = ''
      ProxyRequests off
      ProxyVia Off
      ProxyPreserveHost On

      AddHandler cgi-script .cgi
      AddHandler cgi-script .py
      AddHandler cgi-script .sh
      AddHandler server-parsed .shtml
      AddHandler server-parsed .html

      AddType text/html .shtml

      DirectoryIndex index.html index.cgi index.php index.xhtml index.htm index.py

      Options Includes Indexes SymLinksIfOwnerMatch MultiViews ExecCGI

      <IfModule mod_suexec>
        Suexec On
      </IfModule>
    '';

    virtualHosts = [
      (acmeVhost common.tld)
      redbrickVhost
    ] ++ vhosts;
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}