import { Activity, Cpu, Microchip, HardDrive, Fan, Wifi, Monitor, Volume2, Mouse, Keyboard, Power } from "lucide-react";
import React from "react";

interface SpecRowProps {
  category: string;
  items: { label: string; value: string }[];
}

const SpecRow = ({ category, items }: SpecRowProps) => (
  <>
    <div className="bg-slate-800/50 border-b border-slate-700 px-6 py-4">
      <h4 className="text-cyan-400 font-bold text-lg flex items-center gap-2">
        <Activity className="w-5 h-5" />
        {category}
      </h4>
    </div>
    {items.map((item, index) => (
      <React.Fragment key={index}>
        <div className="bg-slate-900/30 px-6 py-4 hover:bg-slate-800/50 transition-colors">
          <div className="text-gray-400 text-sm">{item.label}</div>
        </div>
        <div className="bg-slate-900/30 px-6 py-4 hover:bg-slate-800/50 transition-colors border-l-2 border-transparent hover:border-cyan-500/50 transition-colors">
          <div className="text-white font-medium">{item.value}</div>
        </div>
      </React.Fragment>
    ))}
  </>
);

export default function Specifications() {
  const specs = [
    {
      category: "Graphics",
      items: [
        { label: "GPU", value: "NVIDIA GeForce RTX 5090" },
        { label: "VRAM", value: "32GB GDDR7" },
        { label: "Ray Tracing", value: "3rd Gen RT Cores" },
        { label: "DLSS", value: "4th Gen AI Renderer" },
        { label: "Outputs", value: "4x HDMI 2.1, 1x DisplayPort 2.1" },
      ]
    },
    {
      category: "Processor",
      items: [
        { label: "CPU", value: "Intel Core i9-14900K" },
        { label: "Cores/Threads", value: "24C / 32T (8P + 16E)" },
        { label: "Base Clock", value: "3.2 GHz" },
        { label: "Boost Clock", value: "Up to 6.0 GHz" },
        { label: "Motherboard", value: "ROG Maximus XII Formula (Z790)" },
      ]
    },
    {
      category: "Memory",
      items: [
        { label: "RAM", value: "128GB DDR5-6000" },
        { label: "Modules", value: "4x 32GB Hyper-X RGB" },
        { label: "CAS Latency", value: "CL36" },
        { label: "XMP Profile", value: "Supported" },
      ]
    },
    {
      category: "Storage",
      items: [
        { label: "Primary SSD", value: "2TB NVMe Gen4 SSD" },
        { label: "Secondary SSD", value: "2TB NVMe Gen4 SSD" },
        { label: "Read Speed", value: "Up to 7000 MB/s" },
        { label: "Write Speed", value: "Up to 6000 MB/s" },
        { label: "Storage Bus", value: "PCIe Gen4 x4" },
      ]
    },
    {
      category: "Cooling",
      items: [
        { label: "Cooling System", value: "Custom Liquid Loop" },
        { label: "Radiators", value: "360mm + 240mm" },
        { label: "Fans", value: "5x ARGB Cooling Fans" },
        { label: "Pump", value: "Low-Noise Ceramic Pump" },
      ]
    },
    {
      category: "Connectivity",
      items: [
        { label: "WiFi", value: "Wi-Fi 7 (802.11be)" },
        { label: "Ethernet", value: "2.5Gb Ethernet" },
        { label: "Bluetooth", value: "Bluetooth 5.3" },
        { label: "USB Ports", value: "USB 3.2 Gen 2x2 (20Gbps)" },
        { label: "Audio", value: "7.1 Channel HD Audio" },
      ]
    },
    {
      category: "Power",
      items: [
        { label: "PSU", value: "1200W 80+ Titanium" },
        { label: "Form Factor", value: "ATX Mid Tower" },
        { label: "Case Material", value: "Tempered Glass + Aluminum" },
        { label: "RGB Lighting", value: "Addressable RGB" },
        { label: "Dimensions", value: "450 x 220 x 480 mm" },
      ]
    }
  ];

  return (
    <section id="specs" className="py-24 relative bg-slate-950 overflow-hidden">
      {/* Background effects */}
      <div className="absolute top-0 left-0 w-full h-1 bg-gradient-to-r from-cyan-500 via-purple-500 to-pink-500 opacity-50"></div>
      
      <div className="container mx-auto px-4 relative z-10">
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
                SPECIFICATIONS
          </h2>
          <p className="text-gray-400">Detailed breakdown of the NEXUS-X ecosystem</p>
        </div>

        <div className="max-w-5xl mx-auto">
          <div className="bg-slate-900 rounded-2xl border border-slate-800 overflow-hidden">
            <div className="grid grid-cols-2">
              {specs.map((section, index) => (
                <div key={index}>
                  <SpecRow 
                    category={section.category} 
                    items={section.items} 
                  />
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
