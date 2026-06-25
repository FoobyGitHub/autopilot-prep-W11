Pushd "%~dp0"
cd "%~dp0"

pnputil -i -a .\VirtualDriver\AsusVirtualDevice.inf

pnputil -i -a .\Touchpad\AsusPTPFilter.inf

pnputil -i -a .\Consumer_Keyboard\AsusConsumerDevFilter.inf

pnputil -i -a .\Consumer_Keyboard\AsusKeyboardFilter.inf
