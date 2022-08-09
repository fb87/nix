{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos-minimal";
  networking.networkmanager.enable = true;

  time.timeZone = "Asia/Ho_Chi_Minh";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    useXkbConfig = true;
  };

  services.printing.enable = true;

  sound.enable = true;
  hardware.pulseaudio.enable = true;

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    packages = with pkgs; [
      firefox
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  services.openssh.enable = true;

  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.allowedUDPPorts = [ ];

  system.stateVersion = "22.05";
}

