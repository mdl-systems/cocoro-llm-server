import { Microchip, Activity, Zap, Fan, HardDrive, Cpu, MemoryStick, Monitor, Wifi, Power } from "lucide-react";

const FeatureCard = ({ 
  icon: Icon, 
  title, 
  description, 
  colorClass 
}: { 
  icon: React.ElementType; 
  title: string; 
  description: string;
  colorClass: string;
}) => {
  return (
    <div className={`glass-panel rounded-2xl p-8 hover:transform hover:scale-105 hover:${colorClass} transition-all duration-300 group`}>
      <div className={`mb-6 p-4 rounded-2xl bg-gradient-to-br ${colorClass.replace('text-', 'from-').replace('text-white', 'to-slate-800')} bg-opacity-20 inline-block`}>
        <Icon className={`w-12 h-12 ${colorClass}`} />
      </div>
      <h3 className="text-2xl font-bold text-white mb-3">{title}</h3>
      <p className="text-gray-400 leading-relaxed">{description}</p>
    </div>
  );
};

export default function Features() {
  const features = [
    {
      icon: Microchip,
      title: "NVIDIA RTX 5090",
      description: "The world's most powerful GPU with 32GB GDDR7 memory and ray tracing acceleration. Experience AI-powered DLSS 4 like never before.",
      colorClass: "text-cyan-400 group-hover:text-cyan-300"
    },
    {
      icon: Cpu,
      title: "Intel Core i9-14900K",
      description: "24 cores (8P + 16E) delivering up to 6.0 GHz boost. Unmatched multi-threaded performance for gaming, streaming, and rendering.",
      colorClass: "text-blue-400 group-hover:text-blue-300"
    },
    {
      icon: MemoryStick,
      title: "128GB DDR5-6000",
      description: "Hyper-X RGB memory with 6000MHz speed and CL36 latency. Optimized for extreme gaming and professional workloads.",
      colorClass: "text-purple-400 group-hover:text-purple-300"
    },
    {
      icon: HardDrive,
      title: "4TB NVMe Gen4",
      description: "Dual PCIe Gen4 M.2 SSDs with 7000MB/s read speeds. Lightning-fast game loading and asset transfer.",
      colorClass: "text-green-400 group-hover:text-green-300"
    },
    {
      icon: Fan,
      title: "Tri-Fan Cooling",
      description: "Custom liquid cooling loop with 360mm radiators and 3 ARGB fans. Keeps components 15°C cooler than air cooling.",
      colorClass: "text-pink-400 group-hover:text-pink-300"
    },
    {
      icon: Wifi,
      title: "Wi-Fi 7 & 2.5G LAN",
      description: "Next-generation wireless connectivity with 40Gbps throughput. Built-in 2.5G Ethernet for competitive gaming.",
      colorClass: "text-orange-400 group-hover:text-orange-300"
    },
  ];

  return (
    <section id="product" className="py-24 relative bg-slate-950">
      <div className="container mx-auto px-4">
        <div className="text-center mb-16">
          <h2 className="text-4xl md:text-6xl font-bold text-white mb-6">
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-cyan-400 to-purple-400">SYSTEM</span>
            <span className="ml-4 text-white">CONFIGURATION</span>
          </h2>
          <p className="text-xl text-gray-400 max-w-2xl mx-auto">
            Every component is carefully selected for maximum performance, reliability, and aesthetic appeal.
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
          {features.map((feature, index) => (
            <FeatureCard 
              key={index}
              {...feature}
            />
          ))}
        </div>
      </div>
    </section>
  );
}
