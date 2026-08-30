import { Construction } from 'lucide-react'
import { Card, EmptyState } from '@/components/ui'

/**
 * Honest stub for routes whose screens are not built on the web yet.
 *
 * Deliberately says what the screen will do rather than pretending to be it —
 * a half-drawn fake page is worse than a clear "not here yet", because it wastes
 * the user's time working out whether it is broken.
 */
export function Placeholder({ title, note }: { title: string; note: string }) {
  return (
    <div className="space-y-6">
      <h1 className="text-xl font-extrabold text-ink">{title}</h1>
      <Card>
        <EmptyState
          icon={<Construction className="h-5 w-5" />}
          title="Not built on the web yet"
          message={`${note} This screen exists in the Android app and is next up for the web.`}
        />
      </Card>
    </div>
  )
}
