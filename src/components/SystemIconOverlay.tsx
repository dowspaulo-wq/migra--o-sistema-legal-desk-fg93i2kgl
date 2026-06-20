import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase/client'

export function SystemIconOverlay() {
  const [systems, setSystems] = useState<{ name: string; image_url: string | null }[]>([])

  useEffect(() => {
    supabase
      .from('case_systems')
      .select('name, image_url')
      .then(({ data }) => {
        if (data) setSystems(data.filter((s) => s.image_url))
      })
  }, [])

  useEffect(() => {
    if (systems.length === 0) return

    const replaceTextWithIcon = () => {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: (node) => {
          if (!node.nodeValue) return NodeFilter.FILTER_REJECT
          const val = node.nodeValue.trim()
          if (systems.some((s) => s.name === val)) {
            const parent = node.parentElement
            if (!parent) return NodeFilter.FILTER_REJECT
            if (parent.hasAttribute('data-system-icon')) return NodeFilter.FILTER_REJECT

            const tag = parent.tagName.toLowerCase()
            if (['script', 'style', 'input', 'textarea', 'option'].includes(tag)) {
              return NodeFilter.FILTER_REJECT
            }
            return NodeFilter.FILTER_ACCEPT
          }
          return NodeFilter.FILTER_REJECT
        },
      })

      const nodesToReplace: { node: Text; system: any }[] = []
      let node
      while ((node = walker.nextNode())) {
        const text = node.nodeValue?.trim()
        const system = systems.find((s) => s.name === text)
        if (system) nodesToReplace.push({ node: node as Text, system })
      }

      nodesToReplace.forEach(({ node, system }) => {
        const parent = node.parentElement
        if (!parent) return
        parent.setAttribute('data-system-icon', 'true')

        if (system.image_url) {
          const img = document.createElement('img')
          img.src = system.image_url
          img.alt = system.name
          img.className = 'w-4 h-4 object-contain inline-block mr-1.5 align-middle shrink-0'
          parent.insertBefore(img, node)
        }
      })
    }

    let timeout: ReturnType<typeof setTimeout>
    const observer = new MutationObserver(() => {
      clearTimeout(timeout)
      timeout = setTimeout(replaceTextWithIcon, 50)
    })

    observer.observe(document.body, { childList: true, subtree: true, characterData: true })
    replaceTextWithIcon()

    return () => {
      observer.disconnect()
      clearTimeout(timeout)
    }
  }, [systems])

  return null
}
