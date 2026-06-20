import { useEffect } from 'react'
import useLegalStore from '@/stores/useLegalStore'

export function SystemIconOverlay() {
  const { state } = useLegalStore()
  const systems = state.caseSystems || []
  const cases = state.cases || []

  useEffect(() => {
    if (systems.length === 0) return

    // Matches standard CNJ process number format
    const processRegex = /\b\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}\b/

    const replaceTextWithIcon = () => {
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: (node) => {
          if (!node.nodeValue) return NodeFilter.FILTER_REJECT
          const val = node.nodeValue.trim()

          // 1. Exact system name match (e.g. standalone "E-proc" text nodes)
          if (systems.some((s) => s.name === val)) {
            const parent = node.parentElement
            if (!parent || parent.hasAttribute('data-system-icon')) return NodeFilter.FILTER_REJECT
            const tag = parent.tagName.toLowerCase()
            if (['script', 'style', 'input', 'textarea', 'option'].includes(tag)) {
              return NodeFilter.FILTER_REJECT
            }
            return NodeFilter.FILTER_ACCEPT
          }

          // 2. Process number match (to append icon next to unmanaged process numbers in any view)
          if (cases.length > 0 && processRegex.test(val)) {
            const parent = node.parentElement
            if (!parent || parent.hasAttribute('data-process-icon')) return NodeFilter.FILTER_REJECT
            // Skip if it's explicitly handled natively by Cases.tsx / CaseDetail.tsx
            if (parent.closest('[data-native-system-icon="true"]')) return NodeFilter.FILTER_REJECT

            const tag = parent.tagName.toLowerCase()
            if (['script', 'style', 'input', 'textarea', 'option'].includes(tag)) {
              return NodeFilter.FILTER_REJECT
            }
            return NodeFilter.FILTER_ACCEPT
          }

          return NodeFilter.FILTER_REJECT
        },
      })

      const nodesToReplace: { node: Text; type: 'system' | 'process'; matchVal: string }[] = []
      let node
      while ((node = walker.nextNode())) {
        const text = node.nodeValue?.trim() || ''
        if (systems.some((s) => s.name === text)) {
          nodesToReplace.push({ node: node as Text, type: 'system', matchVal: text })
        } else {
          const match = text.match(processRegex)
          if (match) {
            nodesToReplace.push({ node: node as Text, type: 'process', matchVal: match[0] })
          }
        }
      }

      nodesToReplace.forEach(({ node, type, matchVal }) => {
        const parent = node.parentElement
        if (!parent) return

        if (type === 'system') {
          parent.setAttribute('data-system-icon', 'true')
          const system = systems.find((s) => s.name === matchVal)
          if (system?.image_url) {
            const img = document.createElement('img')
            img.src = system.image_url
            img.alt = system.name
            img.title = system.name
            img.className = 'w-4 h-4 object-contain inline-block mr-1.5 align-middle shrink-0'
            parent.insertBefore(img, node)
          }
        } else if (type === 'process') {
          parent.setAttribute('data-process-icon', 'true')
          const relatedCase = cases.find((c) => c.number === matchVal)
          if (relatedCase && relatedCase.system) {
            const system = systems.find((s) => s.name === relatedCase.system)
            if (system?.image_url) {
              const img = document.createElement('img')
              img.src = system.image_url
              img.alt = system.name
              img.title = system.name
              img.className = 'w-4 h-4 object-contain inline-block mr-1.5 align-middle shrink-0'
              parent.insertBefore(img, node)
            }
          }
        }
      })
    }

    let timeout: ReturnType<typeof setTimeout>
    const observer = new MutationObserver(() => {
      clearTimeout(timeout)
      timeout = setTimeout(replaceTextWithIcon, 100)
    })

    observer.observe(document.body, { childList: true, subtree: true, characterData: true })
    replaceTextWithIcon()

    return () => {
      observer.disconnect()
      clearTimeout(timeout)
    }
  }, [systems, cases])

  return null
}
