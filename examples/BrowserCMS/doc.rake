Dir["#{Gem.searcher.find('mini_gauge').full_gem_path}/lib/tasks/*.rake"].each { |ext| load ext }

namespace :doc do
    
  desc "Create graphs of for BCMS"
  task :graph do
    %w(doc:mini_gauge:environment_for_graph doc:mini_gauge:clobber 
      doc:mini_gauge:generate_complete_graph
      doc:mini_gauge:generate_class_sources ).collect do |task|

      Rake::Task[task].invoke
    end
    
    @section = Section.first
    
    if @section
      saving_model("01_section_with_pages.dot", "section") do
        @section.to_dot_notation(:title => "A section and its pages", :description => "A section has many child nodes, but only some of those are pages") do |graph|
          @section.child_nodes.each do |child_node|
            # Add two jumps, first section => child_node
            graph.add(:source => @section, :destination => child_node, :label => "@section.child_nodes")
            if child_node.node_type == 'Page'
              # next, child_node => page
              graph.add(:source => child_node, :destination => child_node.node, :label => "child_node.node")
            end
          end
        end
      end
    end    
    
    Rake::Task['doc:mini_gauge:build_pdfs'].invoke
    
  end
end
